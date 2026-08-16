<?php

use App\Services\ConsumptionForecast;
use FlutterSdk\MagicStarter\Support\MigrationHelper;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * What the ledger says about how fast a product is used.
 *
 * ### Why the rate is stored and the days of cover are not
 *
 * The expensive half of a forecast is the ledger walk: bucketing every outflow into days and
 * smoothing the series. That answer only changes when a movement is written, so it is computed
 * there, once, beside `rebuildProductStock`.
 *
 * The cheap half is `on_hand / rate`, and it is deliberately NOT stored. It changes for two
 * reasons rather than one: the quantity on hand, and the rate. Materialising it would make a
 * screen able to disagree with `product_stock` sitting next to it, which is the class of bug
 * `product_stock` itself exists to avoid, and the division costs nothing.
 *
 * ### It is a cache of a derivation, so it can be thrown away
 *
 * Every column here is recomputable from `stock_movements` alone. Deleting the table and letting
 * it refill loses nothing, which is what makes it safe to store a derived number at all (D84's
 * shape: PHP computes, PostgreSQL stores).
 *
 * @see ConsumptionForecast
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('product_forecasts', function (Blueprint $table): void {
            MigrationHelper::primaryKey($table);
            MigrationHelper::foreignKey($table, 'team_id')->constrained()->cascadeOnDelete();

            // One row per product, and it dies with it: a forecast about a product that no longer
            // exists is not history worth keeping, unlike a movement.
            MigrationHelper::foreignKey($table, 'product_id')->constrained()->cascadeOnDelete();

            // **Base units per day, from SBA.** Nullable because the bottom tier has no rate at all:
            // `forecasting.md`'s honesty constraint is that below the movement threshold we show the
            // user's own target and say the history is not there yet, and a zero here would read as
            // "nothing is used" rather than as "we do not know".
            $table->decimal('daily_rate', 12, 6)->nullable();

            // **The smoothed days BETWEEN demands, which SBA computes on the way to the rate.**
            // Stored because the obsolescence rule is "three intervals with nothing", and three
            // intervals is a different number of days for every product. A fixed probability
            // threshold cannot express it: measured by hand at beta 0.1, a weekly item's TSB
            // probability settles at 0.1922 and an every-other-day item's at 0.5333, so any single
            // cut means "three intervals" for one rhythm and something else for every other.
            $table->decimal('mean_interval_days', 10, 4)->nullable();

            // **TSB's demand probability.** SBA freezes a stale estimate for a product a cafe stopped
            // using; this decays on every period without demand, which is the signal that the item is
            // fading, and it is what a screen can show. The DECISION that an item is gone is the
            // interval rule above, because that is the one that means the same thing at every rhythm.
            $table->decimal('demand_probability', 8, 6)->nullable();

            // How many non-zero movements the rate was computed from. This is what decides the tier,
            // and it travels so a screen can say which claim it is allowed to make (D46).
            $table->unsignedInteger('movement_count')->default(0);

            // The already-decided tier, stored rather than derived at read for one reason: the
            // threshold is explicitly a number to instrument and tune, and a stored value makes a
            // change to it visible as a migration rather than as a silent reinterpretation of old
            // rows.
            $table->string('tier', 16);

            // The last day the product was consumed, for the obsolescence sentence and for a human
            // checking the arithmetic against the ledger by hand.
            $table->date('last_demand_on')->nullable();

            // When this was last recomputed, so a stale row is visible rather than assumed fresh.
            $table->timestamp('computed_at');

            $table->timestamps();

            // The dashboard and the running-low screen both ask "which of this tenant's products are
            // short", which is this pair.
            $table->index(['team_id', 'tier']);
        });

        $this->addConstraints();
    }

    public function down(): void
    {
        Schema::dropIfExists('product_forecasts');
    }

    /**
     * Constraints the schema builder has no fluent API for.
     *
     * Raw DDL rather than a violation of D84: a CHECK and a unique index CONSTRAIN, they do not
     * derive.
     */
    private function addConstraints(): void
    {
        // One forecast per product, which is what makes the recompute an upsert rather than an
        // append. A second row would let two screens read two different answers.
        DB::statement('
            ALTER TABLE product_forecasts
            ADD CONSTRAINT product_forecasts_product_unique
            UNIQUE (product_id)
        ');

        // A rate is a quantity per day and cannot be negative. Zero IS allowed and means something
        // real: a product with history whose demand has decayed to nothing.
        DB::statement('
            ALTER TABLE product_forecasts
            ADD CONSTRAINT product_forecasts_rate_is_not_negative
            CHECK (daily_rate IS NULL OR daily_rate >= 0)
        ');

        // A probability is a probability.
        DB::statement('
            ALTER TABLE product_forecasts
            ADD CONSTRAINT product_forecasts_probability_is_a_probability
            CHECK (demand_probability IS NULL OR (demand_probability >= 0 AND demand_probability <= 1))
        ');

        // The closed vocabulary, and the reason it is closed: each tier is a promise about what a
        // sentence may claim (D46), so a value outside this set would be a screen with no rule.
        DB::statement("
            ALTER TABLE product_forecasts
            ADD CONSTRAINT product_forecasts_tier_is_known
            CHECK (tier IN ('none', 'rough', 'forecast'))
        ");

        // **The tier and the rate agree, enforced rather than trusted.** The bottom tier having a
        // rate would let a screen print a number the tier forbids, which is the one failure this
        // whole feature is built to avoid.
        DB::statement("
            ALTER TABLE product_forecasts
            ADD CONSTRAINT product_forecasts_only_the_top_tier_has_a_rate
            CHECK ((tier = 'forecast') = (daily_rate IS NOT NULL))
        ");
    }
};
