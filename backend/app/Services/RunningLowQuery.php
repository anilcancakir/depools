<?php

namespace App\Services;

use App\Models\Product;
use App\Models\Scopes\TeamScope;
use Carbon\CarbonInterface;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Query\JoinClause;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;

/**
 * Which of a tenant's products are short, and by how much.
 *
 * ### Three ways to be short, and they are not interchangeable
 *
 * 1. **Nothing on hand.** No threshold is needed to say a product has run out, so this arm ignores
 *    the target entirely. It is also the only arm that can catch a product the user never set a
 *    target for, which today is every product: the creation form deliberately does not ask, because
 *    `forecasting.md` wants the target asked at the moment it becomes useful.
 * 2. **At or below a target the user set.** An explicit instruction, and it wins over everything
 *    this service infers.
 * 3. **At or below an inferred reorder point**, for a product with enough history to have a rate.
 *    The reorder point is the rate multiplied by how often this tenant shops (D48), which is why
 *    [RestockRhythm] exists and why the phrase "lead time" never appears on screen.
 *
 * ### The multiplication happens in PHP, and that shapes the query
 *
 * D84 and Anılcan's rule: PostgreSQL stores, indexes and constrains; Laravel computes. So
 * `total_quantity <= daily_rate * :days` cannot be a WHERE clause, and the query instead narrows to
 * a SUPERSET the database can express with plain comparisons, which PHP then decides.
 *
 * The superset is bounded by one number: the tenant's highest rate times the rhythm. Any product
 * below its OWN reorder point is below the highest one, so nothing is lost, and every well-stocked
 * product is dropped before it reaches PHP. This is the same trade [ProductListQuery] makes for the
 * expiry window, where PHP computes one date per distinct shelf life and hands them down as
 * bindings.
 *
 * ### Not paginated, deliberately
 *
 * The dates endpoint is not either, for the same reason: the result is already bounded by the
 * question. A tenant is not short of everything, and a screen whose whole job is "what do I need to
 * deal with" is unusable if the answer arrives a page at a time. The ordering is by urgency, which
 * a cursor could not express anyway without materialising it.
 */
final class RunningLowQuery
{
    public function __construct(private readonly RestockRhythm $rhythm) {}

    /**
     * Every short product, most urgent first.
     *
     * Each row carries two attributes the caller needs and the columns do not hold: `reorder_point`,
     * the inferred threshold where one exists, and `days_of_cover`. Both are computed here rather
     * than stored, so neither can disagree with the `product_stock` row it was derived from.
     *
     * @return Collection<int, Product>
     */
    public function shortages(string $teamId, ?CarbonInterface $today = null): Collection
    {
        $restockDays = $this->rhythm->forTeam($teamId, $today);
        $ceiling = $this->highestRate($teamId) * $restockDays;

        return $this->candidates($teamId, $ceiling)
            ->map(function (Product $product) use ($restockDays): Product {
                $onHand = (float) ($product->total_quantity ?? 0);
                $rate = $product->forecast?->hasRate() === true
                    ? (float) $product->forecast->daily_rate
                    : null;

                // NOT `reorder_point`. That is a real column, cast to `decimal:3` and emitted by
                // `ProductResource`, so writing the inferred figure there would replace whatever the
                // user or an import had put in it on the way out to the client.
                $product->inferred_reorder_point = $rate === null ? null : $rate * $restockDays;
                $product->days_of_cover = $product->forecast?->daysOfCover($onHand);

                return $product;
            })
            ->filter(fn (Product $product): bool => $this->isShort($product))
            // Emptiest first, as a fraction of what the product should be holding rather than as an
            // absolute: two of a target of twenty is more urgent than two of a target of three, and
            // the raw shortfall would rank a bulk item above a staple every time. Everything with
            // nothing on hand ties at zero and the name breaks it, so the out-of-stock group is
            // alphabetical, which is what a list you read while walking round a shop wants.
            // Comparators rather than key extractors: `sortBy` given an array calls each entry with
            // BOTH items and uses the return as the comparison, so a one-argument closure here would
            // silently sort by nothing.
            ->sortBy([
                fn (Product $a, Product $b): int => $this->urgency($a) <=> $this->urgency($b),
                fn (Product $a, Product $b): int => strcmp((string) $a->name, (string) $b->name),
            ])
            ->values();
    }

    /**
     * Whether this product is short on any of the three counts.
     *
     * **An explicit target outlives obsolescence, and the inferred threshold does not.**
     * `forecasting.md`'s sixth acceptance criterion asks that an item not consumed for three
     * intervals drops off rather than haunting the list, and that is right for something the app
     * inferred. Applying it to a target the user typed would be an inference overriding an
     * instruction, silently, which is the worse of the two failures: a stale row is annoying and
     * explainable, a dropped one is invisible.
     */
    private function isShort(Product $product): bool
    {
        $onHand = (float) ($product->total_quantity ?? 0);

        if ($onHand <= 0) {
            return true;
        }

        if ($product->par_level !== null && $onHand < (float) $product->par_level) {
            return true;
        }

        if ($product->inferred_reorder_point === null || $product->forecast?->isObsolete() === true) {
            return false;
        }

        return $onHand <= $product->inferred_reorder_point;
    }

    /**
     * How short, as a fraction of what the product should be holding.
     *
     * The larger of the two thresholds is the denominator, because a product carrying both is short
     * against whichever asks for more. Nothing on hand is zero whatever the threshold, and a product
     * with no threshold at all can only be here by being empty, so it is zero too.
     */
    private function urgency(Product $product): float
    {
        $onHand = (float) ($product->total_quantity ?? 0);

        $threshold = max(
            (float) ($product->par_level ?? 0),
            (float) ($product->inferred_reorder_point ?? 0),
        );

        return $threshold > 0 ? $onHand / $threshold : 0.0;
    }

    /**
     * The tenant's highest consumption rate, or zero when nothing has one.
     *
     * One scalar, and it is what lets the third arm of the candidate query be a plain comparison.
     * Zero collapses that arm to "nothing on hand", which the first arm already covers, so a tenant
     * with no forecasts pays for one aggregate and nothing else.
     */
    private function highestRate(string $teamId): float
    {
        return (float) DB::table('product_forecasts')
            ->where('team_id', $teamId)
            ->where('tier', 'forecast')
            ->max('daily_rate');
    }

    /**
     * The superset PHP then decides, with everything the decision needs already loaded.
     *
     * @return Collection<int, Product>
     */
    private function candidates(string $teamId, float $ceiling): Collection
    {
        // **Keyed on the team it was given, and the crossing is stated** (D111). Leaving `TeamScope`
        // on would work from a request and answer nothing from a command, and it would also give
        // this service two sources of tenant: the scope for the products and `$teamId` for the rate
        // and the rhythm. One source cannot disagree with itself.
        //
        // `withoutGlobalScope(TeamScope::class)` and not `withoutGlobalScopes()`, which would take
        // `SoftDeletingScope` with it and put deleted products on the shopping list.
        $query = Product::query()
            ->withoutGlobalScope(TeamScope::class)
            ->where('products.team_id', $teamId);

        return $this->join($query)
            ->with(['stock', 'tags', 'unit', 'primaryImage', 'forecast'])
            ->where(function (Builder $query) use ($ceiling): void {
                $query
                    // Out, including a product with no projection row at all: never stocked and
                    // fully consumed are the same answer to "how much is there".
                    ->whereNull('stock_totals.total_quantity')
                    ->orWhere('stock_totals.total_quantity', '<=', 0)
                    // BELOW the user's own target, matching `ProductListQuery`'s `below_par` axis
                    // and `ProductListItem.isBelowPar`. All three were `<=` and all three are now
                    // `<`: how much to buy is the target minus what is on hand, so a product at
                    // exactly its target produces a shopping line reading "buy 0".
                    ->orWhere(
                        fn (Builder $q): Builder => $q->whereNotNull('products.par_level')
                            ->whereColumn('stock_totals.total_quantity', '<', 'products.par_level'),
                    )
                    // Low enough that its own reorder point MIGHT catch it. The comparison is against
                    // the tenant's highest, so this is a superset and PHP does the per-product test.
                    ->orWhere(
                        fn (Builder $q): Builder => $q->where('product_forecasts.tier', 'forecast')
                            ->where('stock_totals.total_quantity', '<=', $ceiling),
                    );
            })
            ->get();
    }

    /**
     * The projection total and the forecast, joined once rather than queried per row.
     *
     * @param  Builder<Product>  $query
     * @return Builder<Product>
     */
    private function join(Builder $query): Builder
    {
        return $query
            ->select('products.*')
            ->addSelect('stock_totals.total_quantity')
            ->leftJoinSub(
                DB::table('product_stock')
                    ->select('product_id', 'team_id')
                    ->selectRaw('sum(quantity) as total_quantity')
                    ->groupBy('product_id', 'team_id'),
                'stock_totals',
                // On the tenant as well as on the product, for the reason `ProductListQuery` states:
                // the outer query is already scoped, and this closes a projection row whose team
                // disagrees with its product's.
                function (JoinClause $join): void {
                    $join->on('stock_totals.product_id', '=', 'products.id')
                        ->on('stock_totals.team_id', '=', 'products.team_id');
                },
            )
            // Joined rather than only eager-loaded, because the tier is part of the WHERE. The
            // relation is eager-loaded too, and that is not the same query doing the same work twice:
            // this join reads one column for a predicate, the relation hydrates the model the caller
            // reads `daysOfCover` off.
            ->leftJoin('product_forecasts', function (JoinClause $join): void {
                $join->on('product_forecasts.product_id', '=', 'products.id')
                    ->on('product_forecasts.team_id', '=', 'products.team_id');
            });
    }
}
