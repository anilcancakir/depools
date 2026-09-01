<?php

namespace App\Services;

use App\Enums\MovementSource;
use App\Models\Location;
use App\Models\Receipt;
use App\Models\ReceiptLine;
use App\Support\IdempotencyKey;
use Illuminate\Support\Carbon;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;

/**
 * Turning confirmed receipt lines into stock.
 *
 * **This is the only place a receipt reaches the ledger, and it goes through `StockWriter`** like
 * every other write, because `.claude/rules/ledger.md` has one writer and that is the whole point:
 * a second path would eventually forget the lot, the projection rebuild or the tenancy stamp.
 *
 * ### Nothing is written that a person has not agreed to
 *
 * `receipt-ingestion.md` makes per-line confirmation mandatory, so the caller sends the lines it
 * confirmed and this writes those. A line the user rejected is marked and never reaches the ledger;
 * a line they have not looked at yet is simply absent from the request and stays as it was.
 *
 * ### Partial confirmation is the normal case, not an edge
 *
 * A 22-line shop is worked through, and the user may leave halfway. So this commits whatever
 * arrived, leaves the rest alone, and marks the RECEIPT confirmed only once no line is still
 * waiting for a decision. Coming back to a half-committed receipt continues from where it stood,
 * which is what makes the interrupted case resumable rather than a restart.
 */
final class ReceiptCommitter
{
    public function __construct(private readonly StockWriter $writer) {}

    /**
     * Writes the confirmed lines into [$location] and marks them.
     *
     * **Returns nothing, deliberately.** `LedgerWritersTest` pins the set of files that can REACH
     * `stock_movements`, and it detects reachability rather than write verbs, so naming that model
     * even as a return type would put this file in the set. It has no need to: it asks `StockWriter`
     * to append and the caller re-reads the receipt. The rule is that the writer stays one file, and
     * the test enforcing it is worth more than a return value nobody used.
     *
     * @param  Collection<int, ReceiptLine>  $lines  already resolved to this receipt and this tenant
     * @param  array<string, array{quantity: float, product_id: string}>  $decisions  keyed by line id
     */
    public function commit(
        Receipt $receipt,
        Location $location,
        Collection $lines,
        array $decisions,
        ?string $batchKey = null,
        ?string $actorId = null,
    ): void {
        DB::transaction(function () use ($receipt, $location, $lines, $decisions, $batchKey, $actorId): void {
            foreach ($lines as $line) {
                $decision = $decisions[(string) $line->getKey()] ?? null;

                if ($decision === null) {
                    continue;
                }

                $this->commitLine($receipt, $location, $line, $decision, $batchKey, $actorId);
            }

            $this->markReceipt($receipt);
        });
    }

    /**
     * One line: the movement, then the line's own state.
     *
     * @param  array{quantity: float, product_id: string}  $decision
     */
    private function commitLine(
        Receipt $receipt,
        Location $location,
        ReceiptLine $line,
        array $decision,
        ?string $batchKey,
        ?string $actorId,
    ): void {
        $product = $line->product()->getRelated()->newQuery()->findOrFail($decision['product_id']);

        $this->writer->receive(
            product: $product,
            location: $location,
            quantity: $decision['quantity'],
            source: MovementSource::Receipt,
            actorId: $actorId,
            // **Per LINE, not per receipt.** The unique index is `(team_id, idempotency_key)` and it
            // is per movement, so one key on every line would let the first insert win and the rest
            // collide. Keyed on the line id rather than an index, because a client that reorders its
            // payload between retries would otherwise write the same line twice under two keys.
            //
            // **Hashed rather than concatenated, and this was a live overflow.** `"{key}:{uuid}"` is
            // up to 101 characters against a `varchar(64)`, and PostgreSQL raises 22001 rather than
            // truncating: a client sending a UUID as its key 500'd on every commit. Found while the
            // shelf path was being written with the same shape.
            idempotencyKey: IdempotencyKey::forRow($batchKey, (string) $line->getKey()),
            // **The receipt's own date, not now.** A shop entered on Tuesday for a Sunday receipt has
            // to age from Sunday, or every forecast built on it is two days optimistic. Null falls
            // back to now inside the writer.
            context: $receipt->issued_on === null
                ? null
                : new MovementContext(occurredAt: $receipt->issued_on->startOfDay()),
            // D96: the movement points at the LINE, so a user who spots one wrong item on a 22-line
            // shop can have that line undone rather than the whole receipt.
            reference: $line,
        );

        $line->fill([
            'product_id' => $product->getKey(),
            'quantity' => $decision['quantity'],
            'resolution' => 'matched',
            // `manual`, because whatever the cascade proposed, a person is the one who agreed to it.
            // That is also what makes the alias worth writing later: a confirmation is evidence.
            'resolved_by' => 'manual',
            'confirmed_at' => Carbon::now(),
        ])->save();
    }

    /**
     * Marks the receipt confirmed once nothing is still waiting for a decision.
     *
     * An `unresolved` line is one the user has not answered yet, so a receipt holding any of them is
     * still in progress however many movements this call wrote.
     */
    private function markReceipt(Receipt $receipt): void
    {
        $pending = $receipt->lines()->where('resolution', 'unresolved')->exists();

        if ($pending) {
            return;
        }

        $receipt->fill([
            'status' => 'committed',
            'confirmed_at' => Carbon::now(),
        ])->save();
    }
}
