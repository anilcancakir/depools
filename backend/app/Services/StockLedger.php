<?php

namespace App\Services;

use App\Models\Product;
use App\Models\ProductStock;
use App\Models\Scopes\TeamScope;
use App\Models\StockLot;
use Illuminate\Support\Collection;

/**
 * Reads over the ledger: which lot to consume next, and the materialised totals.
 *
 * Nothing here writes a movement. Consumption is a separate concern that will call [fefoLots] to
 * decide WHERE to take from and then append to the ledger itself, so this class stays safe to call
 * from a read path.
 *
 * ### Every query here states that it crosses the tenancy scope, and that is a fix rather than a hole
 *
 * `BelongsToTeam` fails closed: with no authenticated user `TeamScope` matches nothing, and its own
 * docblock names the case this class is ("a queue worker rebuilding a materialised total, say") and
 * says the caller must state the crossing explicitly with a test behind it.
 *
 * Measured before it was changed: [rebuildProductStock] called with no authenticated user found no
 * lots, computed a quantity of zero, took the delete branch, deleted nothing (that query is scoped
 * too) and returned as though it had rebuilt the pair. **A repair that silently does nothing** is
 * precisely the failure D81 accepted responsibility for, so the nightly sweep could not have used it.
 *
 * The rule that makes the crossing safe rather than convenient: **every method here is keyed on an
 * explicit `Product` and location.** Whoever resolved that product already crossed the boundary,
 * through a scoped query or deliberately without one, so re-applying the scope inside adds no
 * safety and only breaks non-request callers. A method taking a tenant-less filter would still need
 * the scope, and there is none here. `grep withoutGlobalScope` lists every crossing in the app, which
 * is the audit this shape is chosen to keep possible.
 */
final class StockLedger
{
    /**
     * The lots to consume from, in the order they should be used.
     *
     * ### An open lot outranks a merely-earlier printed date
     *
     * This is D27 and it is the part that surprises. Pure first-expired-first-out would send a user
     * to a sealed carton dated Tuesday while an opened one dated Friday sits in the fridge, and the
     * opened one is on a much shorter clock the printed date knows nothing about. It is also what
     * anyone actually does: you finish the carton that is open before starting another.
     *
     * So the order is two tiers. Open lots first, then sealed, and inside each tier the binding
     * date ascending with undated lots last.
     *
     * ### The binding date is resolved in PHP, deliberately
     *
     * It is the earlier of `expires_at` and `opened_at + products.opened_shelf_life_days`, which in
     * SQL means a correlated join and a database-specific date expression for every engine this
     * runs on. The set being ordered is the open lots of ONE product at ONE location, which is a
     * handful of rows; paying a portable, readable comparison for that is the right trade, and if
     * a tenant ever has enough lots for it to matter, that is a measurement worth having first.
     *
     * @return Collection<int, StockLot>
     */
    public function fefoLots(Product $product, int|string $locationId): Collection
    {
        /** @var Collection<int, StockLot> $lots */
        $lots = StockLot::query()
            ->withoutGlobalScope(TeamScope::class)
            ->where('product_id', $product->getKey())
            ->where('location_id', $locationId)
            ->whereNull('closed_at')
            ->where('remaining_quantity', '>', 0)
            ->with('product')
            ->get();

        return $lots->sort(function (StockLot $a, StockLot $b): int {
            // Tier one: open before sealed.
            $openness = ($a->opened_at === null ? 1 : 0) <=> ($b->opened_at === null ? 1 : 0);

            if ($openness !== 0) {
                return $openness;
            }

            $dateA = $a->bindingDate();
            $dateB = $b->bindingDate();

            // Undated lots go last inside their tier: a non-perishable has no claim on being used
            // first, and sorting nulls to the front would send every consumption to the flour.
            if ($dateA === null && $dateB === null) {
                return $a->received_at <=> $b->received_at;
            }

            if ($dateA === null) {
                return 1;
            }

            if ($dateB === null) {
                return -1;
            }

            return $dateA <=> $dateB;
        })->values();
    }

    /**
     * Rewrite the materialised totals for one (product, location) pair from the ledger.
     *
     * Rebuilt from scratch rather than adjusted, for the same reason
     * `StockLot::recalculateFromLedger` is: a retried job or a double-fired event converges instead
     * of drifting, and the drift check becomes a comparison rather than a guess.
     *
     * The pair's row is DELETED when the quantity reaches zero and no lots remain, rather than kept
     * at zero. A stock list that shows every product a tenant has ever held at every location they
     * have ever used is not a stock list.
     */
    public function rebuildProductStock(Product $product, int|string $locationId): ?ProductStock
    {
        $lots = StockLot::query()
            ->withoutGlobalScope(TeamScope::class)
            ->where('product_id', $product->getKey())
            ->where('location_id', $locationId)
            ->get();

        $quantity = (float) $lots->sum(static fn (StockLot $lot): float => (float) $lot->remaining_quantity);

        $open = $lots->filter(static fn (StockLot $lot): bool => (float) $lot->remaining_quantity > 0);

        if ($open->isEmpty() && $quantity <= 0) {
            ProductStock::query()
                ->withoutGlobalScope(TeamScope::class)
                ->where('product_id', $product->getKey())
                ->where('location_id', $locationId)
                ->delete();

            return null;
        }

        // The earliest date the pair is bound by, which drives the list screen's expiry badge. It
        // reads the binding date rather than `expires_at`, so an opened lot shortens the badge the
        // same way it shortens FEFO.
        $earliest = $open
            ->map(static fn (StockLot $lot) => $lot->bindingDate())
            ->filter()
            ->sort()
            ->first();

        // Scope-free for the reason above, and here it also prevents a SECOND failure: with the scope
        // active the lookup half matches nothing, so `updateOrCreate` would insert instead of update
        // and collide with the `(team_id, product_id, location_id)` unique index.
        //
        // Keyed on `(product_id, location_id)` without the team, which is not a loosening: a product
        // belongs to exactly one team, so the pair is already unique, and including the team could
        // only ever make the lookup MISS a row it should have updated.
        $stock = ProductStock::query()
            ->withoutGlobalScope(TeamScope::class)
            ->firstOrNew([
                'product_id' => $product->getKey(),
                'location_id' => $locationId,
            ]);

        // Explicit, for the reason `StockWriter::newLot` records at length: `team_id` is deliberately
        // absent from `$fillable` so a controller cannot pass one through from a request, which also
        // means `updateOrCreate` silently DROPPED it here and the row's tenant came from the auth
        // context rather than from the product it belongs to. Identical on a request path, null on
        // every other, so the write failed on a not-null violation naming a column.
        $stock->setAttribute('team_id', $product->team_id);

        $stock->fill([
            'quantity' => $quantity,
            'earliest_expires_at' => $earliest,
            'lots_count' => $open->count(),
        ])->save();

        return $stock;
    }
}
