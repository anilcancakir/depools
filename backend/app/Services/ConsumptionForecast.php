<?php

namespace App\Services;

use App\Enums\MovementReason;
use App\Models\Product;
use App\Models\ProductForecast;
use App\Models\StockMovement;
use Carbon\CarbonInterface;
use Illuminate\Support\Carbon;

/**
 * How fast a product is used, from its own ledger.
 *
 * ### The honesty constraint decides the shape before any arithmetic does
 *
 * `forecasting.md` opens with it: a household or a cafe consumes a given item 2 to 8 times a month,
 * which is very little data and lumpy with it. So below the threshold there is no forecast at all,
 * and the user's own target is what the screen shows. A wrong prediction shown confidently costs
 * more trust than an honest "not yet", and the feature's credibility IS the product.
 *
 * That is why the tier is an output of this class rather than a presentation choice: what a sentence
 * may claim is decided here, once, and the schema's CHECK makes a screen unable to overstate it.
 *
 * ### SBA for the rate, and why not plain Croston
 *
 * Croston separates demand SIZE from the INTERVAL between demands and smooths each, which is what
 * makes it work on a series that is mostly zeros. It over-forecasts by 5 to 18 percent depending on
 * the smoothing constant, and Syntetos-Boylan corrects that bias with a `(1 - alpha/2)` factor. SBA
 * is the practitioner default for intermittent demand.
 *
 * ### TSB for obsolescence, and why it is NOT multiplied into the rate
 *
 * TSB replaces Croston's interval estimate with a demand PROBABILITY updated every period, including
 * the empty ones, so it decays toward zero for a product nobody buys any more. That is the job
 * `forecasting.md` gives it: "TSB decays toward zero instead of freezing a stale estimate, which
 * matters for a product a cafe stopped using".
 *
 * **Multiplying SBA's rate by TSB's probability would double-count the intermittency**, because
 * SBA's rate is already size over interval and the interval already encodes how often demand
 * happens. So the two are kept apart: the rate is SBA's, and the probability is carried beside it as
 * the obsolescence signal a caller reads. An item consumed once and never again keeps its rate and
 * loses its probability, which is the honest description of it.
 *
 * ### No machine learning, and that is a measured call rather than a preference
 *
 * The M5 competition's ML advantage came from cross-learning across millions of SKU-store series and
 * shrinks or reverses at the single-SKU level, which is the only level a single tenant has. Plain
 * exponential smoothing outperformed the large majority of M5 entrants (D7 also forbids the model
 * doing arithmetic, but the accuracy argument stands on its own).
 */
final class ConsumptionForecast
{
    /**
     * Movements below which no rate is computed.
     *
     * Ten, from D8, and `forecasting.md` is explicit that this is "a reasoned starting point, not a
     * sourced constant; no citable minimum exists. Instrument it and tune." It lives here as one
     * constant so tuning it is one edit and a migration of the stored tiers, rather than a search.
     */
    public const FORECAST_THRESHOLD = 10;

    /**
     * Movements below which not even a rough average is offered.
     *
     * Two, because a single observation has no interval at all: one demand gives a size and nothing
     * to divide it by, so there is literally no rate to be rough about.
     */
    public const ROUGH_THRESHOLD = 2;

    /**
     * The smoothing constant for demand SIZE, shared by SBA and TSB.
     *
     * 0.1, which sits in the 0.05 to 0.2 band the intermittent-demand literature uses and which
     * Syntetos and Boylan's own work reports over. Low on purpose: a household's demand is lumpy,
     * and a high alpha would make one big shop swing the rate for weeks.
     */
    private const ALPHA = 0.1;

    /**
     * The smoothing constant for TSB's demand PROBABILITY.
     *
     * The same 0.1, and the consequence is worth stating in periods rather than in decimals: after a
     * demand the probability rises by a tenth of the remaining distance to 1, and every empty day
     * multiplies it by 0.9. So a product last used 30 days ago retains `0.9^30`, about 4 percent of
     * whatever it had, which is the decay curve the obsolescence rule reads.
     *
     * Public because `ProductForecast::demandProbabilityOn` applies the same decay at read time, and
     * two copies of a smoothing constant is how the stored value and the read value drift apart.
     */
    public const BETA = 0.1;

    /**
     * The reason that counts as demand.
     *
     * **Consumption only.** Waste is deliberately excluded even though it is an outflow: the whole
     * reason `waste` is its own reason rather than folded into `consumption` is that waste
     * percentage is a number this product sells, and letting it inflate the consumption rate would
     * make a cafe that throws milk away look like a cafe that sells more milk.
     *
     * `transfer_out` moved shelves rather than leaving, `return` went back to the supplier, and a
     * `stock_take` or a `correction` is a fix to the record rather than something anybody used.
     */
    private const DEMAND = MovementReason::Consumption;

    /**
     * Recompute one product's forecast and store it.
     *
     * **Scope-free, keyed on the product it was given** (D111). This runs from `StockWriter`, which a
     * seeder, a queued import and a console command all reach without an auth context, and
     * `TeamScope` fails closed: applying it here would read an empty ledger and write a forecast of
     * nothing for exactly the callers that cannot pass a team any other way.
     */
    public function refresh(Product $product, ?CarbonInterface $today = null): ProductForecast
    {
        $today = Carbon::parse($today ?? Carbon::today())->startOfDay();

        $daily = $this->dailyDemand($product, $today);
        $count = count(array_filter($daily, static fn (float $amount): bool => $amount > 0));

        $tier = match (true) {
            $count >= self::FORECAST_THRESHOLD => 'forecast',
            $count >= self::ROUGH_THRESHOLD => 'rough',
            default => 'none',
        };

        $probability = $daily === [] ? null : $this->demandProbability($daily);
        $sba = $this->sba($daily);

        $forecast = ProductForecast::query()->withoutGlobalScopes()
            ->firstOrNew(['product_id' => $product->getKey()]);

        $forecast->setAttribute('team_id', $product->team_id);

        $forecast->fill([
            // **Only the top tier carries one**, which the table's own CHECK also enforces. A rate on
            // a `rough` row would be a number the tier forbids sitting one join away from a screen.
            'daily_rate' => $tier === 'forecast' ? $sba['rate'] : null,
            // **Kept at every tier above the floor**, unlike the rate. An interval is an observation
            // rather than a forecast: two demands three days apart is a fact, and the obsolescence
            // rule needs it long before the tenth movement earns a number.
            'mean_interval_days' => $sba['interval'],
            'demand_probability' => $probability,
            'movement_count' => $count,
            'tier' => $tier,
            'last_demand_on' => $this->lastDemandOn($daily, $today),
            'computed_at' => now(),
        ])->save();

        return $forecast;
    }

    /**
     * Consumption per DAY, from the product's first demand to today, zeros included.
     *
     * The zeros are the point. Croston and its descendants are defined over a period grid where most
     * periods are empty, and TSB's decay only happens because the empty days are there to decay
     * across. Summing straight from the movement rows would give a series of demands with no notion
     * of the time between them.
     *
     * Starting at the FIRST demand rather than at the product's creation, because a product added in
     * January and first used in June has no information in those five months: it was not being
     * consumed, it did not exist to be consumed.
     *
     * @return list<float> one entry per day, oldest first
     */
    private function dailyDemand(Product $product, CarbonInterface $today): array
    {
        /** @var array<string, float> $byDay */
        $byDay = StockMovement::query()->withoutGlobalScopes()
            ->where('product_id', $product->getKey())
            ->where('reason', self::DEMAND->value)
            ->where('delta', '<', 0)
            ->orderBy('occurred_at')
            ->get(['occurred_at', 'delta'])
            ->reduce(function (array $carry, StockMovement $movement): array {
                $day = $movement->occurred_at->toDateString();

                // Magnitude: the sign is the ledger's direction and a rate is not negative.
                $carry[$day] = ($carry[$day] ?? 0.0) + abs((float) $movement->delta);

                return $carry;
            }, []);

        if ($byDay === []) {
            return [];
        }

        $first = Carbon::parse(array_key_first($byDay))->startOfDay();
        $series = [];

        for ($day = $first->copy(); $day->lessThanOrEqualTo($today); $day->addDay()) {
            $series[] = $byDay[$day->toDateString()] ?? 0.0;
        }

        return $series;
    }

    /**
     * The Syntetos-Boylan rate, in base units per day.
     *
     * Croston's two smoothings, updated only on a day that had demand:
     *
     *     size'     = size'     + alpha * (demand - size')
     *     interval' = interval' + alpha * (gap    - interval')
     *
     * and then the bias correction that makes it SBA rather than Croston:
     *
     *     rate = (1 - alpha / 2) * size' / interval'
     *
     * Seeded from the FIRST observation rather than from zero, which is the standard treatment: a
     * zero seed would take a dozen demands to climb out of and every early forecast would understate.
     *
     * @param  list<float>  $daily
     * @return array{rate: float, interval: float|null}
     */
    private function sba(array $daily): array
    {
        $size = null;
        $interval = null;
        $gap = 0;

        foreach ($daily as $amount) {
            $gap++;

            if ($amount <= 0) {
                continue;
            }

            if ($size === null) {
                // The first demand seeds the size and has no interval behind it to measure.
                $size = $amount;
            } else {
                $size += self::ALPHA * ($amount - $size);
                $interval = $interval === null
                    ? (float) $gap
                    : $interval + self::ALPHA * ($gap - $interval);
            }

            $gap = 0;
        }

        // One demand and no second: there is an amount and no interval, so there is no rate. The
        // caller cannot reach this, because one demand is below the threshold, and it is here so the
        // arithmetic is total rather than relying on that.
        if ($size === null || $interval === null || $interval <= 0) {
            return ['rate' => 0.0, 'interval' => null];
        }

        return [
            'rate' => (1 - self::ALPHA / 2) * $size / $interval,
            // Returned rather than discarded, because the obsolescence rule is stated in intervals
            // and this is the only place that knows what one is for this product.
            'interval' => $interval,
        ];
    }

    /**
     * TSB's demand probability, updated on EVERY day rather than only the demand ones.
     *
     *     demand:    p = p + beta * (1 - p)
     *     no demand: p = p + beta * (0 - p)   which is p * (1 - beta)
     *
     * That second line is the whole point: it is the only thing in this file that happens because
     * time passed rather than because something was recorded, and it is what stops a product a cafe
     * stopped using from keeping its rate forever.
     *
     * @param  list<float>  $daily
     */
    private function demandProbability(array $daily): float
    {
        // Seeded from the first period, which is a demand by construction: the series starts at the
        // first demand.
        $p = 1.0;

        foreach (array_slice($daily, 1) as $amount) {
            $p += self::BETA * (($amount > 0 ? 1.0 : 0.0) - $p);
        }

        return round($p, 6);
    }

    /**
     * The last day this product was consumed.
     *
     * @param  list<float>  $daily
     */
    private function lastDemandOn(array $daily, CarbonInterface $today): ?Carbon
    {
        for ($offset = count($daily) - 1; $offset >= 0; $offset--) {
            if ($daily[$offset] > 0) {
                return Carbon::parse($today)->subDays(count($daily) - 1 - $offset);
            }
        }

        return null;
    }
}
