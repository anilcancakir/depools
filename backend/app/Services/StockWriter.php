<?php

namespace App\Services;

use App\Enums\ActorType;
use App\Enums\CountOutcome;
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
    /**
     * The width of "the count agreed", in base units.
     *
     * Half of `decimal(_, 3)`'s smallest step, so every difference the column can actually hold is
     * written and nothing else is. See [count].
     */
    private const COUNT_EPSILON = 0.0005;

    public function __construct(private readonly StockLedger $ledger) {}

    /**
     * Every movement written under a batch key, keyed by its own per-line key.
     *
     * **Matched by prefix, so the caller sees lines it did not ask about.** A retry that sends fewer
     * lines than the first attempt would otherwise find exactly what it looked for and read as a
     * complete replay while later rows sat there unreported.
     *
     * `%` and `_` are LIKE wildcards and the key comes from a request, so they are escaped: without
     * it a key of `%` would match every batch this tenant ever recorded. The same hole was measured
     * on the icon search, where `%` alone answered all 4,185 rows.
     *
     * @return Collection<string, StockMovement>
     */
    public function movementsForBatch(string $batchKey): Collection
    {
        $escaped = str_replace(['\\', '%', '_'], ['\\\\', '\%', '\_'], $batchKey);

        return StockMovement::query()
            ->where('idempotency_key', 'like', $escaped.':%')
            ->with('product')
            ->get()
            ->keyBy('idempotency_key');
    }

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
        ?MovementContext $context = null,
    ): StockMovement {
        if ($quantity <= 0) {
            throw new RuntimeException('An inbound movement must bring in a positive quantity.');
        }

        // Invariant 8, refused at the one path that would violate it. A serial-tracked product's
        // quantity is the count of its `product_serials` rows, so a lot created here would be a
        // second, disagreeing answer to "how many": the projection would sum the lot while the
        // product's own definition of quantity counted serials, and neither would be wrong on its
        // own terms. The nightly sweep reports this shape; this is what stops it being written.
        if ($product->tracking_mode === 'serial') {
            throw new RuntimeException(
                'A serial-tracked product does not receive into a lot: register the individual '
                .'units instead, because its quantity is the count of them.',
            );
        }

        return DB::transaction(function () use (
            $product, $location, $quantity, $source, $expiresAt, $lotCode, $actorId, $idempotencyKey,
            $context
        ): StockMovement {
            $lot = $this->newLot($product, [
                'location_id' => $location->getKey(),
                'initial_quantity' => $quantity,
                'expires_at' => $expiresAt,
                'lot_code' => $lotCode,
                // The lot arrived when the movement says it did, so a backdated receipt ages its
                // stock from the same moment its ledger row does.
                'received_at' => $context?->occurredAt ?? now(),
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
                null,
                $context,
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
        ?MovementContext $context = null,
    ): Collection {
        if ($quantity <= 0) {
            throw new RuntimeException('An outbound movement must take out a positive quantity.');
        }

        if (! in_array($reason, [MovementReason::Consumption, MovementReason::Waste, MovementReason::Return], true)) {
            throw new RuntimeException('consume() writes an outflow; use the reason that names it.');
        }

        return DB::transaction(function () use ($product, $location, $quantity, $reason, $source, $actorId, $context): Collection {
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

            $written = $this->takeOut($lots, $quantity, $reason, $source, $actorId, $context);

            $this->ledger->rebuildProductStock($product, $location->getKey());

            return $written;
        });
    }

    /**
     * Reconcile what is physically on a shelf against what the record says (D59).
     *
     * ### A count states an absolute, and the ledger stores deltas
     *
     * So this is the one write path that computes its own quantity. The caller passes what was
     * counted; the difference against the lots at that location is what gets appended, with reason
     * [MovementReason::StockTake] and never [MovementReason::Correction]: `data-model.md` separates a
     * counted correction from a fixed typo, and folding them loses the ability to tell shrinkage from
     * a data-entry mistake.
     *
     * **`stock_take` can only be produced here.** [consume] refuses that reason outright, which is
     * what keeps the vocabulary meaningful: a `stock_take` row in the ledger implies a count actually
     * happened, so the shrinkage figure is not diluted by a client that picked the label by hand.
     *
     * ### Re-committing the same count is a no-op, with no idempotency key
     *
     * Because the quantity is derived rather than given, a retried submit recomputes the delta
     * against the balance the first one produced and finds zero. [receive] needs a key because
     * "bring in 6" means 6 more every time it is asked; "there are 6 on the shelf" is the same fact
     * however often it is stated.
     *
     * ### A match writes nothing
     *
     * Counting and finding agreement is not a movement, and a zero-delta row would not be harmless:
     * `movements_count` decides whether a product has enough history to be forecast, so counts would
     * promote products into the forecast tier on the strength of having been looked at.
     *
     * ### Where a surplus goes, and when it cannot go anywhere
     *
     * Finding MORE than the record is inbound stock, and inbound stock needs a lot, and a lot carries
     * a date the count screen never asked for. The surplus therefore joins the earliest-expiring
     * SEALED lot at that location and inherits its date, on the same reasoning [transfer] inherits
     * the source lot's: the units in front of the counter came from the deliveries already on record,
     * and choosing the earliest of them errs toward warning early rather than late.
     *
     * When there is no sealed lot to inherit from (the balance was zero, or only an opened lot
     * remains) there is no neighbour to reason from, and this returns [CountOutcome::NeedsDate]
     * instead of inventing an expiry. Stock entry owns that row, because it asks for the date with a
     * visible basis and lets the user change it in one tap.
     *
     * **A fractional surplus marks that lot opened**, which is [markOpenedIfPartial]'s inference read
     * in the other direction: a count of "1 carton and 500 ml" can only mean a unit is open. The cost
     * is that the sealed units sharing the lot inherit the shorter opened clock, so they warn earlier
     * than their printed date deserves. That is the safe direction of being wrong, and it is the only
     * one available without splitting the surplus across two lots.
     */
    public function count(
        Product $product,
        Location $location,
        float $counted,
        MovementSource $source = MovementSource::Manual,
        ?string $actorId = null,
    ): StockCountResult {
        if ($counted < 0) {
            throw new RuntimeException('A count states what is on the shelf, so an empty shelf is zero, never less.');
        }

        // Refused before anything is read, so the delta stays honestly absent rather than being
        // computed from lots this product does not use. A serial-tracked quantity IS the number of
        // `product_serials` rows (invariant 8), so summing its lots would answer zero for a shelf
        // holding two drills and report a surplus of the whole count.
        if ($product->tracking_mode === 'serial') {
            return StockCountResult::deferred(CountOutcome::SerialTracked, 0.0);
        }

        return DB::transaction(function () use ($product, $location, $counted, $source, $actorId): StockCountResult {
            $lots = $this->ledger->fefoLots($product, $location->getKey());
            $onHand = (float) $lots->sum(static fn (StockLot $lot): float => (float) $lot->remaining_quantity);
            $delta = $counted - $onHand;

            // Half of the smallest difference `decimal(_, 3)` can hold, so a real 0.001 is written and
            // the float residue of summing decimal strings is not. A literal `=== 0.0` here would
            // append phantom movements of 1e-15 for shelves that agreed perfectly.
            if (abs($delta) < self::COUNT_EPSILON) {
                return StockCountResult::matched();
            }

            if ($delta < 0) {
                // No availability check: the shortfall is `counted - onHand` with `counted` at least
                // zero, so it can never exceed what the lots hold. That is a property of deriving the
                // quantity rather than accepting one, and it is why a count cannot fail the way
                // [consume] can.
                $written = $this->takeOut($lots, -$delta, MovementReason::StockTake, $source, $actorId);

                $this->ledger->rebuildProductStock($product, $location->getKey());

                return StockCountResult::written($written, $delta);
            }

            // `fefoLots` orders open lots before sealed ones and sorts each tier by binding date, so
            // the first sealed lot in that order is the earliest-expiring one. For a sealed lot the
            // binding date IS `expires_at`, because the opened clock needs an `opened_at` to run from.
            $sealed = $lots->first(static fn (StockLot $lot): bool => $lot->opened_at === null);

            if ($sealed === null) {
                return StockCountResult::deferred(CountOutcome::NeedsDate, $delta);
            }

            $this->markOpenedIfPartial($sealed, $delta);

            $movement = $this->append($sealed, $delta, MovementReason::StockTake, $source, $actorId);

            $this->ledger->rebuildProductStock($product, $location->getKey());

            return StockCountResult::written(collect([$movement]), $delta);
        });
    }

    /**
     * Move stock between locations as equal and opposite movements (invariant 5).
     *
     * ### One PAIR per source lot, walking FEFO
     *
     * A move of three from a shelf holding a lot of one and a lot of five is two pairs, not one:
     * expiry belongs to a lot, so the amount leaving each one is its own fact and the lot it
     * arrives in has to carry that lot's date. Invariant 5 is per pair, which is the reading that
     * survives: every outbound row is equal and opposite to exactly one inbound row.
     *
     * The single-lot case, which is most of them, still writes exactly one pair.
     *
     * ### What the two halves of a pair share
     *
     * The doc requires a shared reference and names receipts, invoices and shopping lists as the
     * things a reference usually points at. A transfer has no such document, so both halves point
     * at the DESTINATION LOT that pair created. It is a real row, both halves genuinely share it,
     * and it answers the question the reference exists for: which move was this part of. A grouping
     * column would answer the same question with a second mechanism.
     *
     * ### Why not one movement with two locations
     *
     * Because a movement's `location_id` is what every per-location total sums over. One row
     * carrying both ends would have to be counted twice with opposite signs by every reader, and
     * the first reader to forget would silently make stock appear or vanish.
     *
     * @return array{0: Collection<int, StockMovement>, 1: Collection<int, StockMovement>} outbound
     *                                                                                     then
     *                                                                                     inbound,
     *                                                                                     paired by
     *                                                                                     index
     */
    public function transfer(
        Product $product,
        Location $from,
        Location $to,
        float $quantity,
        MovementSource $source = MovementSource::Manual,
        ?string $actorId = null,
        ?MovementContext $context = null,
    ): array {
        if ($from->is($to)) {
            throw new RuntimeException('A transfer needs two different locations.');
        }

        return DB::transaction(function () use ($product, $from, $to, $quantity, $source, $actorId, $context): array {
            $sourceLots = $this->ledger->fefoLots($product, $from->getKey());
            $available = (float) $sourceLots->sum(static fn (StockLot $lot): float => (float) $lot->remaining_quantity);

            if ($available < $quantity) {
                throw new RuntimeException(
                    'Not enough stock to move: '.$quantity.' requested, '.$available.' at the source.',
                );
            }

            $out = collect();
            $in = collect();
            $remaining = $quantity;

            // **One pair per SOURCE LOT, walking FEFO, and this used to be one pair against the
            // first lot alone.** The availability check above sums every lot on the shelf, so a
            // request larger than the first one passed it and then debited the whole amount from
            // that lot. `StockLot::recompute` clamps at `max($remaining, 0)`, so the overdraft did
            // not surface as a negative lot: it vanished, and the untouched lots still counted in
            // full. Measured on two lots of 1 and 5 with a move of 3: six units existed and eight
            // remained.
            //
            // Splitting also fixes the quieter half. The destination inherited the FIRST lot's
            // dates for the whole amount, so three units crossing a September lot and a December
            // lot all arrived stamped September, and two of them aged three months early.
            foreach ($sourceLots as $sourceLot) {
                if ($remaining <= 0) {
                    break;
                }

                $take = min($remaining, (float) $sourceLot->remaining_quantity);

                // The destination lot inherits ITS OWN source's dates. A carton does not become
                // fresher by being carried to another shelf, and losing the date here is how a
                // transfer would quietly drop a product out of the expiry list.
                $destinationLot = $this->newLot($product, [
                    'location_id' => $to->getKey(),
                    'initial_quantity' => 0,
                    'expires_at' => $sourceLot->expires_at,
                    'lot_code' => $sourceLot->lot_code,
                    'opened_at' => $sourceLot->opened_at,
                    'received_at' => $sourceLot->received_at,
                ]);
                $destinationLot->forceFill(['remaining_quantity' => 0])->save();

                // Invariant 5 holds PER PAIR: each half is equal and opposite to its partner and
                // both carry the destination lot as their reference, so "which move was this part
                // of" still has one answer for every row.
                $out->push($this->append(
                    $sourceLot,
                    -$take,
                    MovementReason::TransferOut,
                    $source,
                    $actorId,
                    reference: $destinationLot,
                    context: $context,
                ));

                $in->push($this->append(
                    $destinationLot,
                    $take,
                    MovementReason::TransferIn,
                    $source,
                    $actorId,
                    reference: $destinationLot,
                    context: $context,
                ));

                $remaining -= $take;
            }

            $this->ledger->rebuildProductStock($product, $from->getKey());
            $this->ledger->rebuildProductStock($product, $to->getKey());

            return [$out, $in];
        });
    }

    /**
     * Take a quantity out along the FEFO order, splitting across lots when one is not enough.
     *
     * Shared by [consume] and [count] rather than duplicated, because the two differ only in the
     * reason they write and in where the quantity came from. The caller checks availability: [consume]
     * has to refuse a request for more than exists, and [count] cannot produce one.
     *
     * @param  Collection<int, StockLot>  $lots  in FEFO order
     * @return Collection<int, StockMovement> one per lot touched
     */
    private function takeOut(
        Collection $lots,
        float $quantity,
        MovementReason $reason,
        MovementSource $source,
        ?string $actorId,
        ?MovementContext $context = null,
    ): Collection {
        $remaining = $quantity;
        $written = collect();

        // **`occurred_at` travels every row, the typed figure travels only when there is one row.**
        // A FEFO outflow turns ONE request into as many movements as it crosses lots, and the figure
        // the person typed describes the request rather than any of those rows: on all of them it
        // sums to more than they said, on one of them it contradicts that row's own delta. So the
        // invariant is "when `entered_quantity` is present it describes THIS row's delta", and the
        // condition for that is simply that the first lot covers the whole amount.
        //
        // Which is the ordinary case rather than a corner: the out sheet's "250 ml" of a one-litre
        // carton is one lot, and it is exactly the conversion D90 exists to keep. Only a request
        // that genuinely drains one lot into the next loses it.
        $first = $lots->first();

        if ($first === null || (float) $first->remaining_quantity < $quantity) {
            $context = $context?->withoutEnteredFigure();
        }

        foreach ($lots as $lot) {
            if ($remaining <= 0) {
                break;
            }

            $take = min($remaining, (float) $lot->remaining_quantity);

            $this->markOpenedIfPartial($lot, $take);

            $written->push(
                $this->append($lot, -$take, $reason, $source, $actorId, null, null, $context),
            );

            $remaining -= $take;
        }

        return $written;
    }

    /**
     * Set `opened_at` when a lot holds a broken unit, without the user declaring it (D27).
     *
     * A consumption that is not a whole number of base units can only have come from opening one:
     * half a carton is not a carton. The user never says "I am opening this", the same way D30
     * keeps the app from asking questions it can infer, so the flag is a consequence of what they
     * recorded rather than a separate step.
     *
     * [count] reads the same evidence in the other direction: a shelf counted as "1 carton and 500
     * ml" holds an open unit whether or not the record knew about it, so a fractional surplus marks
     * the lot it lands in.
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
     * A lot whose tenant comes from its product rather than from the auth context.
     *
     * Invariant 3 requires a lot to belong to the same team as its product, and taking `team_id` from
     * the product is the only way to make that true by construction. `BelongsToTeam`'s creating hook
     * would otherwise fill it from `TeamScope::currentTeamId()`, which is the same value on a request
     * path and NULL everywhere else: a queued receipt parse or an import failed on a not-null
     * violation naming a column, rather than working.
     *
     * `team_id` stays out of `$fillable` on purpose, so this is an explicit assignment and not a key a
     * controller could pass through from `$request->validated()`. That is the one tenancy rule
     * `data-model.md` marks non-negotiable, and the product was itself resolved through the scope, so
     * reading the tenant off it is the auth context arriving transitively rather than a bypass.
     *
     * @param  array<string, mixed>  $attributes
     */
    private function newLot(Product $product, array $attributes): StockLot
    {
        $lot = new StockLot($attributes + ['product_id' => $product->getKey()]);
        $lot->setAttribute('team_id', $product->team_id);
        $lot->save();

        return $lot;
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
        ?MovementContext $context = null,
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

            // **What the person typed, kept beside the derived `delta`** (D90). The magnitude is
            // stored as given: the sign is the delta's job, and a row that carried both would let
            // them disagree.
            'entered_quantity' => $context?->enteredQuantity === null
                ? null
                : abs($context->enteredQuantity),
            'entered_unit' => $context?->enteredUnit,

            // **When it HAPPENED, defaulting to now.** A receipt entered on Tuesday for a Sunday
            // shop has to age from Sunday, or every forecast built on it is two days optimistic.
            // The column and its index have carried that intent since the table was created and
            // nothing could set it, so every row's `occurred_at` equalled its `created_at`.
            'occurred_at' => $context?->occurredAt ?? now(),
        ]);

        // Same reasoning as [newLot]: the movement's tenant is the lot's, which is the product's.
        $movement->setAttribute('team_id', $lot->team_id);

        if ($reference !== null) {
            $movement->reference()->associate($reference);
        }

        $movement->save();

        return $movement;
    }
}
