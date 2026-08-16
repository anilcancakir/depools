<?php

namespace Tests\Feature;

use App\Enums\MovementReason;
use App\Models\Location;
use App\Models\Product;
use App\Models\ProductForecast;
use App\Models\Team;
use App\Models\User;
use App\Services\ConsumptionForecast;
use App\Services\MovementContext;
use App\Services\StockLedger;
use App\Services\StockWriter;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Tests\TestCase;

/**
 * The consumption forecast, checked against arithmetic done by hand.
 *
 * `forecasting.md`'s second acceptance criterion asks that the numbers "reconcile with the ledger by
 * hand", and that is the only way to test a smoother: an assertion computed the same way the code
 * computes it certifies whatever the code does, including the bug.
 *
 * So the two arithmetic tests below carry their working. Anybody can check the expected figure with
 * a calculator, and if the implementation changes the expected number has to be re-derived rather
 * than re-run.
 */
final class ForecastTest extends TestCase
{
    use RefreshDatabase;

    private Product $product;

    private Location $shelf;

    private StockWriter $writer;

    private ConsumptionForecast $forecast;

    protected function setUp(): void
    {
        parent::setUp();

        /** @var User $user */
        $user = User::factory()->createOne(['locale' => 'en']);
        $team = Team::create(['name' => 'Alpha', 'user_id' => $user->getKey()]);
        $user->forceFill(['current_team_id' => $team->getKey()])->save();

        $this->actingAs($user->refresh(), 'sanctum');

        $this->shelf = Location::create(['name' => 'Fridge']);
        $this->product = Product::create(['name' => 'Süt', 'base_unit' => 'C62']);
        $this->writer = new StockWriter(new StockLedger);
        $this->forecast = new ConsumptionForecast;
    }

    /**
     * Consume `$amount` `$daysAgo` days ago, without going through the writer.
     *
     * The writer refuses to take out more than is on hand and walks FEFO, neither of which this is
     * about, and stocking a year of milk to test a smoother would make every case here start with a
     * receipt nobody reads. So the demand series is written directly and the writer's own hook is
     * tested separately, once, below.
     */
    private function demand(float $amount, int $daysAgo): void
    {
        $this->writer->receive($this->product, $this->shelf, $amount);

        $this->writer->consume(
            $this->product,
            $this->shelf,
            $amount,
            context: new MovementContext(Carbon::today()->subDays($daysAgo)),
        );
    }

    private function refresh(): ProductForecast
    {
        return $this->forecast->refresh($this->product);
    }

    public function test_a_product_nobody_has_used_has_no_rate_and_no_tier_above_none(): void
    {
        // The honesty constraint, at its floor: no history means the user's own target is all the
        // screen may show, and a zero rate would read as "nothing is used" rather than "we do not
        // know".
        $row = $this->refresh();

        $this->assertSame('none', $row->tier);
        $this->assertNull($row->daily_rate);
        $this->assertSame(0, $row->movement_count);
    }

    public function test_one_demand_is_still_no_rate(): void
    {
        // One observation gives a size and nothing to divide it by: there is literally no interval,
        // so there is no rate to be rough about.
        $this->demand(1, 3);

        $row = $this->refresh();

        $this->assertSame('none', $row->tier);
        $this->assertNull($row->daily_rate);
        $this->assertSame(1, $row->movement_count);
    }

    public function test_nine_demands_earn_a_bucket_and_never_a_number(): void
    {
        // D8's gate: below ten, the screen may say "roughly" and may not print a figure. The tier is
        // the promise and the null rate is what makes it unbreakable, since a screen cannot render a
        // number that is not there.
        foreach (range(1, 9) as $i) {
            $this->demand(1, $i * 2);
        }

        $row = $this->refresh();

        $this->assertSame('rough', $row->tier);
        $this->assertNull($row->daily_rate);
        $this->assertSame(9, $row->movement_count);
    }

    public function test_ten_demands_earn_a_rate(): void
    {
        foreach (range(1, 10) as $i) {
            $this->demand(1, $i * 2);
        }

        $row = $this->refresh();

        $this->assertSame('forecast', $row->tier);
        $this->assertNotNull($row->daily_rate);
        $this->assertSame(10, $row->movement_count);
    }

    public function test_the_sba_rate_is_what_the_arithmetic_says(): void
    {
        // **The working, so this can be checked with a calculator.**
        //
        // Ten demands of 2 units, exactly every 3 days, oldest 30 days ago and newest 3 days ago.
        //
        // SIZE: seeded at 2 by the first demand, and every update is `size + 0.1 * (2 - size)`,
        // which moves nothing because every demand is 2. So size stays exactly 2.
        //
        // INTERVAL: seeded at 3 by the SECOND demand (the first has no interval behind it), and
        // every update is `interval + 0.1 * (3 - interval)`, which also moves nothing. So interval
        // stays exactly 3.
        //
        // SBA: `(1 - alpha/2) * size / interval` = `0.95 * 2 / 3` = 0.633333...
        //
        // The constant series is deliberate: it makes the expected value derivable by hand rather
        // than by running the smoother, which is the difference between a test and a snapshot.
        foreach (range(1, 10) as $i) {
            $this->demand(2, $i * 3);
        }

        $row = $this->refresh();

        $this->assertEqualsWithDelta(0.633333, (float) $row->daily_rate, 0.000001);
    }

    public function test_the_bias_correction_is_present_rather_than_plain_croston(): void
    {
        // Croston would answer `size / interval` = 2/3 = 0.6667 on the series above, and it is known
        // to over-forecast by 5 to 18 percent. SBA's `(1 - alpha/2)` is exactly the 5 percent
        // correction at this alpha, so the two are distinguishable by one assertion.
        foreach (range(1, 10) as $i) {
            $this->demand(2, $i * 3);
        }

        $croston = 2 / 3;

        $this->assertEqualsWithDelta(
            $croston * 0.95,
            (float) $this->refresh()->daily_rate,
            0.000001,
            'the rate matches plain Croston, so the SBA correction is missing',
        );
    }

    public function test_days_of_cover_is_divided_at_read_rather_than_stored(): void
    {
        // Six units at two thirds of a unit a day is nine days, and the figure is a division the
        // caller does against whatever is on hand right now. Storing it would let it disagree with
        // the `product_stock` row beside it.
        foreach (range(1, 10) as $i) {
            $this->demand(2, $i * 3);
        }

        $row = $this->refresh();

        $this->assertEqualsWithDelta(9.47, $row->daysOfCover(6.0), 0.01);
        $this->assertEqualsWithDelta(18.95, $row->daysOfCover(12.0), 0.01);
    }

    public function test_a_lower_tier_has_no_days_of_cover_to_give(): void
    {
        $this->demand(1, 2);
        $this->demand(1, 4);

        $this->assertNull($this->refresh()->daysOfCover(10.0));
    }

    public function test_waste_is_not_demand(): void
    {
        // **The reason `waste` exists as its own reason.** A cafe throwing milk away is not a cafe
        // selling more milk, and folding the two would inflate the rate AND destroy the waste
        // percentage this feature sells.
        $this->writer->receive($this->product, $this->shelf, 20);

        foreach (range(1, 12) as $i) {
            $this->writer->consume(
                $this->product,
                $this->shelf,
                1,
                MovementReason::Waste,
                context: new MovementContext(Carbon::today()->subDays($i)),
            );
        }

        $row = $this->refresh();

        $this->assertSame(0, $row->movement_count);
        $this->assertSame('none', $row->tier);
    }

    public function test_a_transfer_is_not_demand_either(): void
    {
        // It moved shelves. Nothing left the tenant and nothing needs rebuying.
        $other = Location::create(['name' => 'Pantry']);

        $this->writer->receive($this->product, $this->shelf, 20);

        foreach (range(1, 12) as $i) {
            $this->writer->transfer($this->product, $this->shelf, $other, 1);
            $this->writer->transfer($this->product, $other, $this->shelf, 1);
        }

        $this->assertSame(0, $this->refresh()->movement_count);
    }

    public function test_the_probability_decays_with_time_rather_than_with_writes(): void
    {
        // **The half that would be dead code if it were computed only on write.** A product consumed
        // ten times and then never again has its probability frozen at the moment it was still being
        // used, so the decay has to happen when the value is READ.
        //
        // TSB's empty-period update is `p * (1 - beta)`, and every day since the last recompute is
        // empty by construction, so twenty days is `p * 0.9^20` = about 12 percent of what it was.
        foreach (range(1, 10) as $i) {
            $this->demand(1, 30 + $i);
        }

        $row = $this->refresh();

        $atWrite = $row->demandProbabilityOn(Carbon::today());

        $this->assertNotNull($atWrite);

        $this->assertEqualsWithDelta(
            $atWrite * (0.9 ** 20),
            $row->demandProbabilityOn(Carbon::today()->addDays(20)),
            0.000001,
        );
    }

    public function test_the_interval_is_what_the_arithmetic_says(): void
    {
        // Ten demands exactly two days apart. The interval seeds at 2 on the second demand and every
        // update is `interval + 0.1 * (2 - interval)`, which moves nothing, so it stays exactly 2.
        // The obsolescence rule is stated in these, so it has to be checkable on its own.
        foreach (range(1, 10) as $i) {
            $this->demand(1, $i * 2);
        }

        $this->assertEqualsWithDelta(2.0, (float) $this->refresh()->mean_interval_days, 0.000001);
    }

    public function test_an_item_consumed_and_then_abandoned_goes_obsolete(): void
    {
        // `forecasting.md`'s sixth acceptance criterion: an item not consumed for three intervals
        // drops off rather than haunting the list. Every two days here, so three intervals is six
        // days, and the last demand was yesterday.
        foreach (range(0, 9) as $i) {
            $this->demand(1, 1 + $i * 2);
        }

        $row = $this->refresh();

        $this->assertFalse($row->isObsolete(Carbon::today()));
        $this->assertFalse($row->isObsolete(Carbon::today()->addDays(4)));
        $this->assertTrue($row->isObsolete(Carbon::today()->addDays(10)));
    }

    public function test_the_threshold_is_the_items_own_rhythm_and_not_a_fixed_number_of_days(): void
    {
        // **The measurement that rejected a fixed probability cut.** A weekly item and an
        // every-other-day item settle at very different TSB probabilities (0.1922 and 0.5333 at beta
        // 0.1, computed by hand), so any single threshold means "three intervals" for one of them and
        // something else for the other. Stated in intervals, both agree.
        //
        // Ten weekly demands, the last one yesterday: three intervals is 21 days, so ten days on it
        // is still wanted and thirty days on it is not.
        foreach (range(0, 9) as $i) {
            $this->demand(1, 1 + $i * 7);
        }

        $row = $this->refresh();

        $this->assertEqualsWithDelta(7.0, (float) $row->mean_interval_days, 0.000001);
        $this->assertFalse($row->isObsolete(Carbon::today()->addDays(10)));
        $this->assertTrue($row->isObsolete(Carbon::today()->addDays(30)));
    }

    public function test_a_product_still_being_used_is_not_obsolete(): void
    {
        // The direction that matters most: dropping a line somebody still needs is the failure a
        // user notices, and a fixed probability cut did exactly this to a weekly item.
        foreach (range(1, 10) as $i) {
            $this->demand(1, $i * 7);
        }

        $this->assertFalse($this->refresh()->isObsolete(Carbon::today()));
    }

    public function test_one_demand_has_no_rhythm_to_have_stopped(): void
    {
        // No interval means nothing is known about how often this happens, so nothing can be said
        // about it having stopped either.
        $this->demand(1, 400);

        $row = $this->refresh();

        $this->assertNull($row->mean_interval_days);
        $this->assertFalse($row->isObsolete(Carbon::today()));
    }

    public function test_consuming_through_the_writer_refreshes_the_forecast(): void
    {
        // The hook, tested once. Everything above drives the service directly, which would let the
        // whole feature be unreachable in production without a single red test.
        $this->writer->receive($this->product, $this->shelf, 10);
        $this->writer->consume($this->product, $this->shelf, 1);

        $row = ProductForecast::query()->withoutGlobalScopes()
            ->where('product_id', $this->product->getKey())
            ->first();

        $this->assertNotNull($row, 'consuming wrote no forecast, so the hook never ran');
        $this->assertSame(1, $row->movement_count);
    }

    public function test_receiving_alone_writes_no_forecast(): void
    {
        // A receipt cannot change the demand series, so walking the ledger for it would be a full
        // scan producing the number it already had.
        $this->writer->receive($this->product, $this->shelf, 10);

        $this->assertSame(
            0,
            ProductForecast::query()->withoutGlobalScopes()
                ->where('product_id', $this->product->getKey())->count(),
        );
    }

    public function test_the_forecast_belongs_to_the_products_tenant(): void
    {
        // Written scope-free from a hook a seeder and a queue reach, so the team has to come from the
        // product rather than from an auth context that may not exist (D111).
        $this->writer->receive($this->product, $this->shelf, 5);
        $this->writer->consume($this->product, $this->shelf, 1);

        $row = ProductForecast::query()->withoutGlobalScopes()->sole();

        $this->assertSame($this->product->team_id, $row->team_id);
    }
}
