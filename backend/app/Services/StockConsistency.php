<?php

namespace App\Services;

use App\Models\GlobalProduct;
use App\Models\OffProduct;
use App\Models\Product;
use App\Models\Scopes\TeamScope;
use App\Models\StockLot;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * The scheduled consistency check D81 calls mandatory, and the four invariants it exists to catch.
 *
 * ### Why this is not a safety net
 *
 * D81 chose an application-maintained projection over a database trigger. A trigger makes invariant 1
 * structurally true: no path can append a movement without moving the projection, whichever surface
 * wrote it. Choosing the service instead moved that guarantee into a promise, and D81 wrote the price
 * down at the time: "here it is the only thing that catches the failure this design permits, so it
 * ships with the feature rather than after it". This is the invoice.
 *
 * The same shape appears three more times, for the same reason each time: a CHECK cannot see another
 * table, and D84 rules out the trigger that could.
 *
 * | Rule | Why the database cannot hold it |
 * |---|---|
 * | invariant 1 | the projection lives in a different table from the ledger it sums |
 * | invariant 2 | a lot's total sums rows in a different table |
 * | invariant 8 | lots and serials are two tables, and exclusivity spans both |
 * | invariant 9 | a serial-tracked quantity is a COUNT in a third table |
 * | D88 | the fold is `Str::ascii` in PHP, so no index expression can verify it |
 *
 * ### Detect in SQL, decide in PHP
 *
 * Every check aggregates in one query and compares in PHP, rather than loading rows and summing them.
 * That is not in tension with D84: an aggregate in an ad-hoc SELECT is not a stored function, a
 * procedure or a generated column, and `Product::quantityFromLedger` already sums this way.
 *
 * D88's check is the exception and it is the honest cost of that decision: the fold only exists in
 * PHP, so the only way to verify it is to read every name and recompute. It chunks for that reason.
 *
 * ### The ledger wins, but only where a rule says which side is right
 *
 * Six checks are repairable because the invariant names the authority: the ledger. Three are not,
 * because no rule this code could apply decides them. A product holding both a lot with stock and a
 * serial has two quantities and nothing in the data says which is the shelf; picking one would
 * destroy the evidence that a writer bypassed the service, which per D81 is the actual finding.
 *
 * ### It runs with no authenticated user, on purpose
 *
 * Every query here is scope-free, because a sweep that only saw one tenant would be a sweep that
 * missed the drift. `LedgerWithoutAuthTest` covers the paths this calls into; `ConsistencyTest`
 * covers that the sweep itself crosses tenants.
 */
final class StockConsistency
{
    public function __construct(private readonly StockLedger $ledger) {}

    /**
     * Every finding in the database, in dependency order.
     *
     * **The order is load-bearing rather than cosmetic, and it is the repair order.** A projection is
     * derived from its lots, so repairing the projection first rebuilds it from lot totals that are
     * themselves still wrong, and the drift comes straight back: `--fix` reported "repaired" and then
     * failed its own re-sweep, which is how this order was found rather than reasoned out.
     *
     * @return Collection<int, ConsistencyFinding>
     */
    public function sweep(): Collection
    {
        return collect()
            ->concat($this->lotFindings())
            ->concat($this->projectionFindings())
            ->concat($this->trackingModeFindings())
            ->concat($this->serialFindings())
            ->concat($this->normalisationFindings())
            ->values();
    }

    /**
     * Put one finding right, using the authority its invariant names.
     *
     * Rebuilt from the ledger rather than adjusted by the difference, so running it twice converges
     * instead of overshooting, which is the same reason `rebuildProductStock` rewrites rather than
     * increments.
     */
    public function repair(ConsistencyFinding $finding): void
    {
        if (! $finding->repairable) {
            throw new RuntimeException(
                "The `{$finding->check}` check has no automatic repair: {$finding->subject}. "
                .'Deciding it needs someone to look at the shelf.',
            );
        }

        match ($finding->check) {
            'projection_drift', 'projection_missing', 'projection_orphaned' => $this->repairProjection($finding),
            'lot_drift', 'lot_negative' => $this->repairLot($finding),
            'name_normalized_drift' => $this->repairName($finding),
            default => throw new RuntimeException("No repair is wired for `{$finding->check}`."),
        };
    }

    /**
     * Invariant 1: for every (product, location), the projection equals the sum of the ledger.
     *
     * Three shapes, because "the projection is wrong" has three forms and the third is the one a
     * naive comparison misses entirely: a row that should not exist at all. `rebuildProductStock`
     * deletes a pair once it holds nothing, so a surviving zero row is a stock list showing a product
     * on a shelf that does not have it.
     *
     * @return Collection<int, ConsistencyFinding>
     */
    private function projectionFindings(): Collection
    {
        $ledger = DB::table('stock_movements')
            ->selectRaw('team_id, product_id, location_id, SUM(delta) AS ledger')
            ->groupBy('team_id', 'product_id', 'location_id');

        $findings = collect();

        DB::query()
            ->fromSub($ledger, 'l')
            ->leftJoin('product_stock as s', function ($join): void {
                $join->on('s.product_id', '=', 'l.product_id')
                    ->on('s.location_id', '=', 'l.location_id');
            })
            ->select('l.team_id', 'l.product_id', 'l.location_id', 'l.ledger', 's.id as stock_id', 's.quantity')
            ->orderBy('l.product_id')
            ->each(function (object $row) use ($findings): void {
                $ledgerQuantity = $this->scale($row->ledger);
                $pair = "product {$row->product_id} at location {$row->location_id}";
                $context = [
                    'product_id' => $row->product_id,
                    'location_id' => $row->location_id,
                ];

                if ($row->stock_id === null) {
                    if (bccomp($ledgerQuantity, '0.000', 3) === 0) {
                        // No projection and nothing to project. `rebuildProductStock` removes the pair
                        // rather than keeping it at zero, so absence is the correct state here.
                        return;
                    }

                    $findings->push(new ConsistencyFinding(
                        check: 'projection_missing',
                        invariant: 1,
                        teamId: $row->team_id,
                        subject: $pair,
                        expected: $ledgerQuantity,
                        actual: 'no product_stock row',
                        repairable: true,
                        context: $context,
                    ));

                    return;
                }

                if (bccomp($ledgerQuantity, $this->scale($row->quantity), 3) !== 0) {
                    $findings->push(new ConsistencyFinding(
                        check: 'projection_drift',
                        invariant: 1,
                        teamId: $row->team_id,
                        subject: $pair,
                        expected: $ledgerQuantity,
                        actual: $this->scale($row->quantity),
                        repairable: true,
                        context: $context,
                    ));
                }
            });

        return $findings->concat($this->orphanedProjectionFindings());
    }

    /**
     * A projection row describing nothing: no movements at all, or a quantity of zero.
     *
     * Both are what a rebuild would remove, and both present to a user as a product sitting on a
     * shelf that does not have it.
     *
     * @return Collection<int, ConsistencyFinding>
     */
    private function orphanedProjectionFindings(): Collection
    {
        return DB::table('product_stock as s')
            ->select('s.id', 's.team_id', 's.product_id', 's.location_id', 's.quantity')
            ->where(function ($query): void {
                $query->whereNotExists(function ($sub): void {
                    $sub->from('stock_movements as m')
                        ->whereColumn('m.product_id', 's.product_id')
                        ->whereColumn('m.location_id', 's.location_id')
                        ->selectRaw('1');
                })->orWhere('s.quantity', '<=', 0);
            })
            ->get()
            ->map(fn (object $row): ConsistencyFinding => new ConsistencyFinding(
                check: 'projection_orphaned',
                invariant: 1,
                teamId: $row->team_id,
                subject: "product {$row->product_id} at location {$row->location_id}",
                expected: 'no product_stock row',
                actual: $this->scale($row->quantity),
                repairable: true,
                context: [
                    'product_id' => $row->product_id,
                    'location_id' => $row->location_id,
                ],
            ));
    }

    /**
     * Invariant 2: a lot's remaining equals its initial plus the sum of its deltas, and is never
     * negative.
     *
     * `lot_overdrawn` is the clause the clamp hides. `recalculateFromLedger` stores `max($sum, 0)`, so
     * a ledger that drove a lot below zero leaves a lot sitting at exactly zero and looking correct.
     * Comparing against the UNCLAMPED sum is the only way that surfaces, and it is not repairable:
     * the missing quantity left the shelf somehow, and writing a compensating movement is a decision
     * about what happened rather than arithmetic.
     *
     * @return Collection<int, ConsistencyFinding>
     */
    private function lotFindings(): Collection
    {
        $deltas = DB::table('stock_movements')
            ->selectRaw('stock_lot_id, SUM(delta) AS delta')
            ->whereNotNull('stock_lot_id')
            ->groupBy('stock_lot_id');

        return DB::table('stock_lots as lo')
            ->leftJoinSub($deltas, 'm', 'm.stock_lot_id', '=', 'lo.id')
            ->selectRaw('lo.id, lo.team_id, lo.initial_quantity, lo.remaining_quantity, COALESCE(m.delta, 0) AS delta')
            ->get()
            ->flatMap(function (object $row): array {
                $unclamped = bcadd($this->scale($row->initial_quantity), $this->scale($row->delta), 3);
                $expected = bccomp($unclamped, '0.000', 3) < 0 ? '0.000' : $unclamped;
                $actual = $this->scale($row->remaining_quantity);
                $findings = [];

                if (bccomp($actual, '0.000', 3) < 0) {
                    $findings[] = new ConsistencyFinding(
                        check: 'lot_negative',
                        invariant: 2,
                        teamId: $row->team_id,
                        subject: "lot {$row->id}",
                        expected: 'at least 0.000',
                        actual: $actual,
                        repairable: true,
                        context: ['lot_id' => $row->id],
                    );
                } elseif (bccomp($expected, $actual, 3) !== 0) {
                    $findings[] = new ConsistencyFinding(
                        check: 'lot_drift',
                        invariant: 2,
                        teamId: $row->team_id,
                        subject: "lot {$row->id}",
                        expected: $expected,
                        actual: $actual,
                        repairable: true,
                        context: ['lot_id' => $row->id],
                    );
                }

                if (bccomp($unclamped, '0.000', 3) < 0) {
                    $findings[] = new ConsistencyFinding(
                        check: 'lot_overdrawn',
                        invariant: 2,
                        teamId: $row->team_id,
                        subject: "lot {$row->id}",
                        expected: 'a ledger that never goes below 0.000',
                        actual: $unclamped,
                        repairable: false,
                        context: ['lot_id' => $row->id],
                    );
                }

                return $findings;
            });
    }

    /**
     * Invariant 8: a product holds lots or serials, never both.
     *
     * The write paths refuse this now, so a finding here means something reached the tables without
     * going through them: a raw query, an `insert()`, a seeder. That is exactly the evidence D81 says
     * matters, which is why it is reported rather than repaired.
     *
     * @return Collection<int, ConsistencyFinding>
     */
    private function trackingModeFindings(): Collection
    {
        return DB::table('products as p')
            ->select('p.id', 'p.team_id', 'p.name', 'p.tracking_mode')
            ->whereNull('p.deleted_at')
            ->whereExists(function ($sub): void {
                $sub->from('stock_lots as lo')
                    ->whereColumn('lo.product_id', 'p.id')
                    ->where('lo.remaining_quantity', '>', 0)
                    ->selectRaw('1');
            })
            ->whereExists(function ($sub): void {
                $sub->from('product_serials as se')
                    ->whereColumn('se.product_id', 'p.id')
                    ->whereNull('se.released_at')
                    ->selectRaw('1');
            })
            ->get()
            ->map(fn (object $row): ConsistencyFinding => new ConsistencyFinding(
                check: 'tracking_mode_conflict',
                invariant: 8,
                teamId: $row->team_id,
                subject: "product {$row->id} ({$row->name})",
                expected: 'stock in lots or in serials',
                actual: 'both, while tracking_mode is '.$row->tracking_mode,
                repairable: false,
                context: ['product_id' => $row->id],
            ));
    }

    /**
     * Invariant 9: a serial-tracked product's quantity is the count of its held serials, and every
     * movement moves exactly one unit.
     *
     * @return Collection<int, ConsistencyFinding>
     */
    private function serialFindings(): Collection
    {
        $findings = DB::table('products as p')
            ->selectRaw('
                p.id, p.team_id, p.name,
                (SELECT COALESCE(SUM(m.delta), 0) FROM stock_movements m WHERE m.product_id = p.id) AS ledger,
                (SELECT COUNT(*) FROM product_serials se WHERE se.product_id = p.id AND se.released_at IS NULL) AS held
            ')
            ->where('p.tracking_mode', 'serial')
            ->whereNull('p.deleted_at')
            ->get()
            ->reject(fn (object $row): bool => bccomp($this->scale($row->ledger), $this->scale($row->held), 3) === 0)
            ->map(fn (object $row): ConsistencyFinding => new ConsistencyFinding(
                check: 'serial_quantity_drift',
                invariant: 9,
                teamId: $row->team_id,
                subject: "product {$row->id} ({$row->name})",
                expected: $this->scale($row->held).' held serials',
                actual: $this->scale($row->ledger).' in the ledger',
                repairable: false,
                context: ['product_id' => $row->id],
            ));

        $fractional = DB::table('stock_movements as m')
            ->join('products as p', 'p.id', '=', 'm.product_id')
            ->select('m.id', 'm.team_id', 'm.delta', 'p.id as product_id')
            ->where('p.tracking_mode', 'serial')
            ->whereRaw('ABS(m.delta) <> 1')
            ->get()
            ->map(fn (object $row): ConsistencyFinding => new ConsistencyFinding(
                check: 'serial_unit_delta',
                invariant: 9,
                teamId: $row->team_id,
                subject: "movement {$row->id} on product {$row->product_id}",
                expected: 'a delta of exactly 1.000 or -1.000',
                actual: $this->scale($row->delta),
                repairable: false,
                context: ['movement_id' => $row->id],
            ));

        return $findings->concat($fractional);
    }

    /**
     * D88: `name_normalized` agrees with the fold of `name`.
     *
     * The gap `NormalisesName` names rather than implies: `Model::query()->update(['name' => ...])`
     * bypasses mutators AND observers, so the stored fold goes stale, the row still looks present, and
     * the cascade quietly stops finding it. Its docblock promised this check by name and it did not
     * exist, which is why the whole trait's guarantee rested on nothing.
     *
     * The one check that cannot be an aggregate, because D84 puts the fold in PHP. Chunked for that
     * reason: the catalog tables are the two that grow.
     *
     * @return Collection<int, ConsistencyFinding>
     */
    private function normalisationFindings(): Collection
    {
        $findings = collect();

        // The flag is whether the table has a tenant at all. `global_products` and `off_products` are
        // the SHARED catalog, so selecting `team_id` across all three fails on a missing column, and a
        // finding on one of them belongs to no team rather than to an unknown one.
        $models = [
            Product::class => true,
            GlobalProduct::class => false,
            OffProduct::class => false,
        ];

        foreach ($models as $model => $tenanted) {
            $model::query()
                ->withoutGlobalScope(TeamScope::class)
                ->select($tenanted ? ['id', 'team_id', 'name', 'name_normalized'] : ['id', 'name', 'name_normalized'])
                ->chunkById(500, function (Collection $rows) use ($findings, $model, $tenanted): void {
                    foreach ($rows as $row) {
                        $expected = $model::normaliseName($row->name);

                        if ($expected === $row->name_normalized) {
                            continue;
                        }

                        $findings->push(new ConsistencyFinding(
                            check: 'name_normalized_drift',
                            invariant: null,
                            teamId: $tenanted ? $row->team_id : null,
                            subject: class_basename($model)." {$row->getKey()} ({$row->name})",
                            expected: (string) $expected,
                            actual: (string) $row->name_normalized,
                            repairable: true,
                            context: ['model' => $model, 'id' => (string) $row->getKey()],
                        ));
                    }
                });
        }

        return $findings;
    }

    private function repairProjection(ConsistencyFinding $finding): void
    {
        $product = Product::query()
            ->withoutGlobalScope(TeamScope::class)
            ->withTrashed()
            ->findOrFail($finding->context['product_id']);

        $this->ledger->rebuildProductStock($product, $finding->context['location_id']);
    }

    private function repairLot(ConsistencyFinding $finding): void
    {
        StockLot::query()
            ->withoutGlobalScope(TeamScope::class)
            ->findOrFail($finding->context['lot_id'])
            ->recalculateFromLedger();
    }

    /**
     * Reassigning `name` runs the mutator, which writes both columns in one assignment. So the repair
     * is the same code path that should have run in the first place, rather than a second fold that
     * could disagree with it.
     */
    private function repairName(ConsistencyFinding $finding): void
    {
        /** @var class-string<Model> $model */
        $model = $finding->context['model'];

        $row = $model::query()
            ->withoutGlobalScope(TeamScope::class)
            ->findOrFail($finding->context['id']);

        $row->name = $row->name;
        $row->save();
    }

    /**
     * The schema's own scale, on every driver.
     *
     * `bccomp` on a raw driver value would compare `'10'` against `'10.000'` correctly but `'10.0'`
     * against `'10.00'` only by luck, and PostgreSQL, a SUM over an empty set and an integer COUNT
     * all hand back different shapes. Three places matches `decimal(12,3)`.
     */
    private function scale(int|float|string|null $value): string
    {
        return bcadd((string) ($value ?? 0), '0', 3);
    }
}
