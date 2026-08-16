<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTeam;
use App\Services\ConsumptionForecast;
use Carbon\CarbonInterface;
use FlutterSdk\MagicStarter\Support\ConditionallyUsesUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Support\Carbon;

/**
 * What the ledger says about how fast one product is used.
 *
 * A cache of a derivation: every column is recomputable from `stock_movements` alone, which is what
 * makes storing it safe. The migration carries the reasoning about which half is stored and which is
 * divided at read time.
 *
 * @see ConsumptionForecast
 */
final class ProductForecast extends Model
{
    use BelongsToTeam;
    use ConditionallyUsesUuids;

    /**
     * How many of an item's OWN intervals may pass before it is treated as no longer wanted.
     *
     * Three, straight from `forecasting.md`'s sixth acceptance criterion: "an item not consumed for
     * three intervals drops off the shopping list rather than persisting".
     *
     * **This was a fixed probability threshold first, and measuring it is what rejected that.** TSB
     * decays by `1 - beta` per empty day, so a product's probability settles near its own demand
     * FREQUENCY: computed by hand at beta 0.1, a weekly item sits at 0.1922 and an every-other-day
     * item at 0.5333. Any single cut therefore means "three intervals" for one rhythm and something
     * else for every other, and a cut at a tenth reported a healthy weekly item as dead seven days
     * after its last use.
     *
     * So the decay is still what fades, and the DECISION is stated in the item's own intervals,
     * which is the one form that means the same thing at every rhythm.
     */
    public const OBSOLETE_AFTER_INTERVALS = 3;

    /** @var list<string> */
    protected $fillable = [
        'team_id',
        'product_id',
        'daily_rate',
        'mean_interval_days',
        'demand_probability',
        'movement_count',
        'tier',
        'last_demand_on',
        'computed_at',
    ];

    protected function casts(): array
    {
        return [
            'daily_rate' => 'decimal:6',
            'mean_interval_days' => 'decimal:4',
            'demand_probability' => 'decimal:6',
            'movement_count' => 'integer',
            'last_demand_on' => 'date',
            'computed_at' => 'datetime',
        ];
    }

    public function product(): BelongsTo
    {
        return $this->belongsTo(Product::class);
    }

    /**
     * Whether this product may claim a number.
     *
     * The tier is what D46 turns into a SHAPE of sentence: ten or more movements earns a figure, two
     * to nine earns a bucket and never a number at any precision, and below that a bare ratio with
     * no time in it.
     */
    public function hasRate(): bool
    {
        return $this->tier === 'forecast' && $this->daily_rate !== null;
    }

    /**
     * The demand probability as of today, rather than as of the last write.
     *
     * **The decay has to happen at READ, and this is not an approximation of TSB but exactly it.**
     * The stored value is only recomputed when a consumption movement is written, and TSB's update
     * for an empty period is `p = p * (1 - beta)`. Every day between `computed_at` and today is
     * empty by construction, because a demand on any of them would have triggered a recompute. So
     * multiplying by `(1 - beta)` once per elapsed day gives the same number the full walk would.
     *
     * Getting this wrong is what would make the whole obsolescence half dead code: a product
     * consumed ten times and then never again has its probability frozen at the moment it was still
     * being used, and nothing would ever lower it.
     */
    public function demandProbabilityOn(?CarbonInterface $today = null): ?float
    {
        if ($this->demand_probability === null) {
            return null;
        }

        $elapsed = $this->computed_at->startOfDay()->diffInDays(
            Carbon::parse($today ?? Carbon::today())->startOfDay(),
        );

        return (float) $this->demand_probability * (1 - ConsumptionForecast::BETA) ** max(0, $elapsed);
    }

    /**
     * Whether the tenant appears to have stopped using this.
     *
     * Three of the item's own intervals with nothing, which is the rule that lets a caller drop a
     * line without knowing what a smoothing constant is.
     *
     * Never true for a product with no interval yet: one demand and no second says nothing about a
     * rhythm, so it cannot say the rhythm has stopped either.
     */
    public function isObsolete(?CarbonInterface $today = null): bool
    {
        if ($this->mean_interval_days === null || $this->last_demand_on === null) {
            return false;
        }

        $elapsed = $this->last_demand_on->startOfDay()->diffInDays(
            Carbon::parse($today ?? Carbon::today())->startOfDay(),
        );

        return $elapsed > self::OBSOLETE_AFTER_INTERVALS * (float) $this->mean_interval_days;
    }

    /**
     * How many days the quantity on hand covers, or null when nothing may be claimed.
     *
     * **Divided here rather than stored**, and the reason is in the migration: it changes with the
     * quantity as well as with the rate, so a materialised copy could disagree with the
     * `product_stock` row beside it.
     *
     * A rate of zero is a real answer and not a division to guard against: it means a product with
     * history that has stopped moving, and "how long will it last" has no number for something
     * nothing is using.
     */
    public function daysOfCover(float $onHand): ?float
    {
        if (! $this->hasRate()) {
            return null;
        }

        $rate = (float) $this->daily_rate;

        return $rate > 0 ? $onHand / $rate : null;
    }
}
