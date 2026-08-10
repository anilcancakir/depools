<?php

namespace App\Services;

use App\Enums\ActorType;
use App\Enums\MovementReason;
use App\Enums\MovementSource;
use App\Models\Location;
use App\Models\Product;
use App\Models\StockLot;
use App\Models\StockMovement;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * The only thing that writes stock.
 *
 * Every method here appends to the ledger and then refreshes what the ledger derives. Nothing else
 * in the application writes `stock_movements`, `stock_lots.remaining_quantity` or `product_stock`,
 * which is what makes the drift check in invariant 1 meaningful: drift is evidence of a writer
 * that bypassed this class, not of an arithmetic error inside it.
 *
 * Every method runs in a transaction. A half-written transfer is the failure mode that matters:
 * stock leaves one shelf, the second insert fails, and the tenant's total is quietly short with no
 * row explaining where it went.
 */
final class StockWriter
{
    public function __construct(private readonly StockLedger $ledger) {}

    /**
     * Bring stock in. Creates the lot the movement references.
     *
     * A lot is created for EVERY inbound movement, dated or not, because the lot is the unit
     * expiry attaches to and a non-perishable simply has a null date. Making the lot conditional
     * would mean two shapes of inbound stock and a branch at every consumer of it.
     */
    public function receive(
        Product $product,
        Location $location,
        float $quantity,
        MovementSource $source = MovementSource::Manual,
        ?string $expiresAt = null,
        ?string $lotCode = null,
        ?string $actorId = null,
        ?string $idempotencyKey = null,
    ): StockMovement {
        if ($quantity <= 0) {
            throw new RuntimeException('An inbound movement must bring in a positive quantity.');
        }

        return DB::transaction(function () use (
            $product, $location, $quantity, $source, $expiresAt, $lotCode, $actorId, $idempotencyKey
        ): StockMovement {
            $lot = StockLot::create([
                'product_id' => $product->getKey(),
                'location_id' => $location->getKey(),
                'initial_quantity' => $quantity,
                'expires_at' => $expiresAt,
                'lot_code' => $lotCode,
                'received_at' => now(),
            ]);

            // The lot already holds `initial_quantity`, so the movement's delta would double it if
            // `recalculateFromLedger` added both. It does not: it computes initial + sum(deltas),
            // and the purchase row IS that initial amount expressed as a ledger fact. So the lot is
            // created at zero and the ledger fills it, which keeps the ledger the only author.
            $lot->forceFill(['initial_quantity' => 0, 'remaining_quantity' => 0])->save();

            $movement = $this->append(
                $lot,
                $quantity,
                MovementReason::Purchase,
                $source,
                $actorId,
                $idempotencyKey,
            );

            $this->ledger->rebuildProductStock($product, $location->getKey());

            return $movement;
        });
    }

    /**
     * Take stock out, choosing lots by FEFO and splitting across them when one is not enough.
     *
     * Returns one movement per lot touched, because a consumption spanning two lots is two facts:
     * the ledger has to say which carton each unit came out of or expiry tracking stops working
     * the moment a second lot exists.
     *
     * @return Collection<int, StockMovement>
     */
    public function consume(
        Product $product,
        Location $location,
        float $quantity,
        MovementReason $reason = MovementReason::Consumption,
        MovementSource $source = MovementSource::Manual,
        ?string $actorId = null,
    ): Collection {
        if ($quantity <= 0) {
            throw new RuntimeException('An outbound movement must take out a positive quantity.');
        }

        if (! in_array($reason, [MovementReason::Consumption, MovementReason::Waste, MovementReason::Return], true)) {
            throw new RuntimeException('consume() writes an outflow; use the reason that names it.');
        }

        return DB::transaction(function () use ($product, $location, $quantity, $reason, $source, $actorId): Collection {
            $lots = $this->ledger->fefoLots($product, $location->getKey());
            $available = (float) $lots->sum(static fn (StockLot $lot): float => (float) $lot->remaining_quantity);

            if ($available < $quantity) {
                // Refused rather than clamped. Taking out more than exists is either a miscount or
                // stock that arrived without being recorded, and both are facts the user should
                // learn now rather than discover as a silently-zeroed shelf later.
                throw new RuntimeException(
                    'Not enough stock: '.$quantity.' requested, '.$available.' on hand at this location.',
                );
            }

            $remaining = $quantity;
            $written = collect();

            foreach ($lots as $lot) {
                if ($remaining <= 0) {
                    break;
                }

                $take = min($remaining, (float) $lot->remaining_quantity);

                $this->markOpenedIfPartial($lot, $take);

                $written->push(
                    $this->append($lot, -$take, $reason, $source, $actorId),
                );

                $remaining -= $take;
            }

            $this->ledger->rebuildProductStock($product, $location->getKey());

            return $written;
        });
    }

    /**
     * Move stock between locations as exactly two equal and opposite movements (invariant 5).
     *
     * ### What the two halves share
     *
     * The doc requires a shared reference and names receipts, invoices and shopping lists as the
     * things a reference usually points at. A transfer has no such document, so both halves point
     * at the DESTINATION LOT, which a transfer creates exactly one of. It is a real row, both
     * halves genuinely share it, and it answers the question the reference exists for: which move
     * was this part of. A grouping column would answer the same question with a second mechanism.
     *
     * ### Why not one movement with two locations
     *
     * Because a movement's `location_id` is what every per-location total sums over. One row
     * carrying both ends would have to be counted twice with opposite signs by every reader, and
     * the first reader to forget would silently make stock appear or vanish.
     *
     * @return array{0: StockMovement, 1: StockMovement} outbound then inbound
     */
    public function transfer(
        Product $product,
        Location $from,
        Location $to,
        float $quantity,
        MovementSource $source = MovementSource::Manual,
        ?string $actorId = null,
    ): array {
        if ($from->is($to)) {
            throw new RuntimeException('A transfer needs two different locations.');
        }

        return DB::transaction(function () use ($product, $from, $to, $quantity, $source, $actorId): array {
            $sourceLots = $this->ledger->fefoLots($product, $from->getKey());
            $available = (float) $sourceLots->sum(static fn (StockLot $lot): float => (float) $lot->remaining_quantity);

            if ($available < $quantity) {
                throw new RuntimeException(
                    'Not enough stock to move: '.$quantity.' requested, '.$available.' at the source.',
                );
            }

            $sourceLot = $sourceLots->first();

            // The destination lot inherits the source's dates. A carton does not become fresher by
            // being carried to another shelf, and losing the date here is how a transfer would
            // quietly drop a product out of the expiry list.
            $destinationLot = StockLot::create([
                'product_id' => $product->getKey(),
                'location_id' => $to->getKey(),
                'initial_quantity' => 0,
                'expires_at' => $sourceLot->expires_at,
                'lot_code' => $sourceLot->lot_code,
                'opened_at' => $sourceLot->opened_at,
                'received_at' => $sourceLot->received_at,
            ]);
            $destinationLot->forceFill(['remaining_quantity' => 0])->save();

            $out = $this->append(
                $sourceLot,
                -$quantity,
                MovementReason::TransferOut,
                $source,
                $actorId,
                reference: $destinationLot,
            );

            $in = $this->append(
                $destinationLot,
                $quantity,
                MovementReason::TransferIn,
                $source,
                $actorId,
                reference: $destinationLot,
            );

            $this->ledger->rebuildProductStock($product, $from->getKey());
            $this->ledger->rebuildProductStock($product, $to->getKey());

            return [$out, $in];
        });
    }

    /**
     * Set `opened_at` when a sealed lot is broken into, without the user declaring it (D27).
     *
     * A consumption that is not a whole number of base units can only have come from opening one:
     * half a carton is not a carton. The user never says "I am opening this", the same way D30
     * keeps the app from asking questions it can infer, so the flag is a consequence of what they
     * recorded rather than a separate step.
     */
    private function markOpenedIfPartial(StockLot $lot, float $take): void
    {
        if ($lot->opened_at !== null) {
            return;
        }

        if (fmod($take, 1.0) === 0.0) {
            return;
        }

        $lot->forceFill(['opened_at' => now()])->save();
    }

    /**
     * Append one row to the ledger.
     */
    private function append(
        StockLot $lot,
        float $delta,
        MovementReason $reason,
        MovementSource $source,
        ?string $actorId,
        ?string $idempotencyKey = null,
        ?StockLot $reference = null,
    ): StockMovement {
        $movement = new StockMovement([
            'product_id' => $lot->product_id,
            'location_id' => $lot->location_id,
            'stock_lot_id' => $lot->getKey(),
            'delta' => $delta,
            'reason' => $reason,
            'source' => $source,
            'actor_type' => $actorId === null ? ActorType::System : ActorType::User,
            'actor_id' => $actorId,
            'idempotency_key' => $idempotencyKey,
            'occurred_at' => now(),
        ]);

        if ($reference !== null) {
            $movement->reference()->associate($reference);
        }

        $movement->save();

        return $movement;
    }
}
