<?php

namespace App\Services;

use App\Enums\MovementSource;
use App\Models\Location;
use App\Models\ShelfCandidate;
use App\Models\ShelfRead;
use App\Support\IdempotencyKey;
use Illuminate\Support\Carbon;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;

/**
 * Turning accepted shelf candidates into stock.
 *
 * `ReceiptCommitter`'s shape, deliberately, including the two calls it does NOT make.
 *
 * ### It goes through `StockWriter` rather than through `stock/receive-batch`
 *
 * That endpoint takes one location and many lines and would fit a shelf exactly, and it carries
 * idempotency, replay and product creation this class does not. It is still not reused, for the
 * reason `.claude/rules/ledger.md` gives: `StockWriter` is the one writer, and reaching the ledger
 * through a controller would put an HTTP shape between a service and a table. `ReceiptCommitter`
 * made the same call for the same problem, and the two paths staying alike is worth more than the
 * machinery.
 *
 * The cost is named rather than hidden: a candidate the user accepted as a NEW product needs that
 * product to exist first, so the client creates it through `POST products` and sends the id. On a
 * shelf of five new products that is five requests a batch endpoint would have folded into one.
 * `receive-batch` is where to look if that ever becomes the thing worth fixing.
 *
 * ### Returns nothing, deliberately
 *
 * `LedgerWritersTest` pins the set of files that can REACH `stock_movements` and it detects
 * reachability rather than write verbs, so naming that model even as a return type would put this
 * file in the set. It has no need to: it asks `StockWriter` to append and the caller re-reads.
 *
 * ### It contributes no photograph hash to the shared catalogue, and that is deliberate
 *
 * `CatalogueContributor` is not called from here at all. A new product a shelf review names is
 * created through `POST products`, which contributes its TEXT the way every other product does and
 * sends no `image_phash`, so no shelf hash ever reaches `global_products`.
 *
 * That asymmetry with the single-product path is the point rather than an oversight. A photograph of
 * one box is a picture of a product, and a globally readable hash of it is a cache key. A photograph
 * of a SHELF is a picture of a room, and a hash of it in a table every tenant reads would be a
 * membership oracle: anyone could ask whether a given picture of a given room had been taken.
 *
 * ### Nothing is written that a person has not agreed to
 *
 * D60 makes the accept count the SETTLED count, never the region count: six regions yielded four
 * products in the fixture, and a button promising six would have written an unnamed bottle and a
 * price label the recogniser mistook for stock. So the caller sends decisions per region and this
 * writes those; a region absent from the request is left exactly as it was, which is what makes an
 * interrupted review resumable rather than a restart.
 */
final class ShelfCommitter
{
    public function __construct(private readonly StockWriter $writer) {}

    /**
     * Writes the accepted candidates into [$location] and marks them.
     *
     * @param  Collection<int, ShelfCandidate>  $candidates  already resolved to this read and tenant
     * @param  array<array-key, array{quantity: float, product_id: string}>  $accepted  keyed by region
     * @param  list<int|string>  $rejected  regions the user said were not products
     */
    public function commit(
        ShelfRead $shelf,
        Location $location,
        Collection $candidates,
        array $accepted,
        array $rejected,
        ?string $batchKey = null,
        ?string $actorId = null,
    ): void {
        // **Both sides folded to strings before anything is compared.** A JSON body sends
        // `rejected: [2, 6]` as integers and `accepted: {"2": ...}` as string keys, because PHP
        // makes every object key a string, so a strict `in_array('2', [2, 6], true)` is false and
        // every rejection would have silently done nothing. Normalising once beats remembering which
        // side is which at two call sites.
        $refused = array_map('strval', $rejected);
        $agreed = [];

        foreach ($accepted as $region => $decision) {
            $agreed[(string) $region] = $decision;
        }

        DB::transaction(function () use ($shelf, $location, $candidates, $agreed, $refused, $batchKey, $actorId): void {
            foreach ($candidates as $candidate) {
                $region = (string) $candidate->region;

                // **A region already answered is skipped, both ways.** The API is keyed by region
                // and treats an absent one as untouched, which invites a resumed client to re-send
                // its whole accepted set; without this that is either a unique violation on the
                // idempotency key or, with a fresh key, a second movement that doubles the stock
                // while the candidate's own quantity is overwritten with the single figure.
                //
                // It also refuses to reject a region whose movement is already in the ledger, which
                // would otherwise show a rejected row beside stock that is still there. A correction
                // is a compensating movement (`ledger.md`), and that is not this call's job.
                if ($candidate->isAnswered()) {
                    continue;
                }

                if (in_array($region, $refused, true)) {
                    // **Marked rather than deleted, and D60 says why**: a row that vanished on
                    // rejection is one the user cannot un-reject, which is the same argument D51
                    // makes for a reversed movement staying visible.
                    //
                    // `resolved_by` becomes `manual` too, because on this table it is the only trace
                    // that a person decided anything, and a row reading `rejected` beside
                    // `resolved_by: alias` credits the refusal to the resolver.
                    $candidate->fill([
                        'resolution' => 'rejected',
                        'product_id' => null,
                        'resolved_by' => 'manual',
                        'confirmed_at' => Carbon::now(),
                    ])->save();

                    continue;
                }

                if (isset($agreed[$region])) {
                    $this->commitCandidate($location, $candidate, $agreed[$region], $batchKey, $actorId);
                }

                // Anything else keeps the state the read left it in. A region the user has not
                // answered yet is not a rejection, and treating it as one would throw away the half
                // of the review they have not reached.
            }

            $this->markRead($shelf);
        });
    }

    /**
     * One candidate: the movement, then the candidate's own state.
     *
     * @param  array{quantity: float, product_id: string}  $decision
     */
    private function commitCandidate(
        Location $location,
        ShelfCandidate $candidate,
        array $decision,
        ?string $batchKey,
        ?string $actorId,
    ): void {
        $product = $candidate->product()->getRelated()->newQuery()->findOrFail($decision['product_id']);

        $this->writer->receive(
            product: $product,
            location: $location,
            quantity: $decision['quantity'],
            // **`Photo`, which the vocabulary already had.** Everything a camera put into stock says
            // so, and that is the audit distinction the ledger exists to keep: a shelf count and a
            // hand-typed delivery must not read alike three months later.
            source: MovementSource::Photo,
            actorId: $actorId,
            // Per CANDIDATE, not per read. The unique index is `(team_id, idempotency_key)` and it is
            // per movement, so one key across a shelf would let the first insert win and the rest
            // collide. Keyed on the candidate id rather than the region, because a re-read renumbers
            // the regions and a retry would then write the same product under a second key.
            // **Hashed rather than concatenated**, because `"{key}:{uuid}"` is up to 97 characters
            // into a `varchar(64)` and PostgreSQL raises 22001 rather than truncating. See
            // [IdempotencyKey] for the arithmetic and for why the receipt path had the same bug.
            idempotencyKey: IdempotencyKey::forRow($batchKey, (string) $candidate->getKey()),
            // **No `MovementContext`, unlike the receipt.** A receipt carries the date it was issued
            // and stock has to age from that; a shelf photograph is taken now, so `now` is not a
            // fallback here, it is the truth.
            reference: $candidate,
        );

        $candidate->fill([
            'product_id' => $product->getKey(),
            'quantity' => $decision['quantity'],
            'resolution' => 'matched',
            // `manual`, because whatever the resolver proposed, a person is the one who agreed to it.
            'resolved_by' => 'manual',
            // The marker that makes this call idempotent per region and that `markRead` counts.
            'confirmed_at' => Carbon::now(),
        ])->save();
    }

    /**
     * Marks the read confirmed once nothing is still waiting for a decision.
     *
     * **Counted on the candidate's own `confirmed_at`, not on `resolution`, and that distinction was
     * a real defect.** The resolver auto-matches a catalogued product with no user involvement, so a
     * region can be `matched` and still be one nobody has looked at: two auto-matched products, the
     * user accepts one and stops, and a read with an unanswered region confirmed itself.
     *
     * What that cost is not cosmetic. `confirmed_at` starts D94's clock, so an early one moves the
     * photograph from the 90-day unconfirmed window to the 30-day confirmed one, and it tells the
     * client a review is finished that is not.
     */
    private function markRead(ShelfRead $shelf): void
    {
        if ($shelf->candidates()->whereNull('confirmed_at')->exists()) {
            return;
        }

        $shelf->fill(['confirmed_at' => Carbon::now()])->save();
    }
}
