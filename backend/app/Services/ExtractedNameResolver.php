<?php

namespace App\Services;

use App\Models\Product;
use App\Models\ProductAlias;
use App\Models\ReceiptLine;
use App\Models\ShelfCandidate;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Collection;

/**
 * Turning a till's abbreviation into one of the tenant's own products.
 *
 * **The hard part of receipt ingestion, and it is not an OCR problem.** `ai-design.md` says it
 * plainly: Turkish thermal receipts truncate to fit the paper ("PNR SUT 1LT", "ORG KEM TAV"), so
 * perfect character recognition still leaves a string that has to become a real product.
 *
 * ### Two of the four steps, and the gap is deliberate
 *
 * The designed cascade is: an exact and normalised match against the tenant's own rows, then
 * embedding similarity, then model normalisation through `TextNormalizationGateway`, then ask the
 * user. Steps 2 and 3 have no substrate yet: nothing in this codebase has ever produced an embedding
 * (`global_products` carries a `vector(1536)` column that no writer fills) and the text-normalisation
 * gateway does not exist. So this runs step 1 and falls through to step 4, which is the honest
 * shape rather than a partial guess: an unresolved line is a line the user is asked about, and that
 * is a state the review screen was drawn for.
 *
 * When the missing steps land they slot in between, and nothing here changes: the resolution is
 * already recorded per line with WHICH step answered it.
 *
 * ### The alias table is the compounding half
 *
 * `ai-design.md`: "Every resolution the user confirms strengthens step 1 for next time. This is
 * where the moat compounds." So aliases are consulted BEFORE products: a tenant who has once told us
 * that "PNR SUT 1LT" is their Pınar Süt gets that answer for free forever, and a name the till
 * prints will never match a product name a person typed.
 *
 * ### It resolves, it does not commit
 *
 * A resolved row is `matched` and points at a product, and NOTHING has moved in the ledger. Per-line
 * confirmation is mandatory (`receipt-ingestion.md`) and D60 makes the shelf's accept count the
 * settled count rather than the region count, so on both paths this only ever prepares what the user
 * is about to be asked about.
 *
 * **Which is exactly why it touches nothing already decided.** Both callers leave earlier rows in
 * place when a retry fails, and this used to fill `resolution` on any row it was handed: a shelf
 * candidate the user had REJECTED flipped back to `matched`, and a committed one lost its `manual`
 * mark and could be re-pointed at a different product than the movement already references. The
 * filter in [resolve] is the fix, and it closes the same hole on the receipt path's re-extract.
 */
final class ExtractedNameResolver
{
    /**
     * Resolves every undecided row of one extraction, in one pass over two lookups.
     *
     * **Two queries for the whole set rather than two per row.** A 25-line shop, or a twelve-region
     * shelf, would otherwise be 50 or 24 round trips on a path a person is waiting on, and both
     * lookups answer a set just as cheaply as they answer one.
     *
     * @param  Collection<int, ReceiptLine|ShelfCandidate>  $rows  already
     *                                                             scoped to one
     *                                                             document and
     *                                                             one tenant
     */
    public function resolve(Collection $rows): void
    {
        // **Only the rows nobody has decided yet, which was a real defect before it was a filter.**
        // A re-extract or a re-read leaves earlier rows in place, and this class fills `product_id`,
        // `resolution` and `resolved_by` unconditionally: a candidate the user REJECTED flipped back
        // to `matched`, and a committed one lost its `manual` mark and could be re-pointed at a
        // different product than the movement already references.
        $rows = $rows->filter(
            static fn ($row): bool => (string) $row->resolution === 'unresolved',
        );

        $needles = $rows
            ->pluck('raw_name_normalized')
            ->filter(static fn (?string $value): bool => $value !== null && $value !== '')
            ->unique()
            ->values();

        if ($needles->isEmpty()) {
            return;
        }

        $aliases = ProductAlias::query()
            ->whereIn('alias_normalized', $needles)
            ->pluck('product_id', 'alias_normalized');

        // Only the names no alias already answered. A tenant with a full alias table then pays for
        // one query rather than two.
        $unaliased = $needles->reject(static fn (string $needle): bool => $aliases->has($needle));

        $products = $unaliased->isEmpty()
            ? collect()
            : Product::query()
                ->whereIn('name_normalized', $unaliased)
                // **`pluck` keyed on the fold, which silently keeps ONE product per name.** Two rows
                // folding to the same normalised name is possible (the column is not unique), and
                // picking either would be a guess presented as a match. `groupBy` first, so a name
                // with more than one owner falls through to the user instead.
                ->get(['id', 'name_normalized'])
                ->groupBy('name_normalized')
                ->reject(static fn (Collection $group): bool => $group->count() > 1)
                ->map(static fn (Collection $group): string => (string) $group->first()->getKey());

        foreach ($rows as $row) {
            $needle = (string) $row->raw_name_normalized;

            if ($aliases->has($needle)) {
                $this->match($row, (string) $aliases->get($needle), 'alias');

                continue;
            }

            if ($products->has($needle)) {
                $this->match($row, (string) $products->get($needle), 'own_product');
            }

            // Anything else keeps the column default, `unresolved`, which is what puts the line in
            // front of the user. Not an error and not a failure of this class: the abbreviation is
            // one nothing has seen before, and asking is the designed answer.
        }
    }

    /**
     * Points one extracted row at a product.
     */
    private function match(Model $row, string $productId, string $by): void
    {
        $row->fill([
            'product_id' => $productId,
            'resolution' => 'matched',
            'resolved_by' => $by,
        ])->save();
    }
}
