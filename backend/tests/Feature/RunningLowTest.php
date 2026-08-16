<?php

namespace Tests\Feature;

use App\Models\Location;
use App\Models\Product;
use App\Models\Team;
use App\Models\User;
use App\Services\MovementContext;
use App\Services\RestockRhythm;
use App\Services\StockLedger;
use App\Services\StockWriter;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Tests\TestCase;

/**
 * `GET api/v1/running-low`, the diagnosis half of D57.
 *
 * Three ways to be short and they are not interchangeable, so each gets its own test rather than one
 * fixture exercising all three: the arms differ in what they need (nothing, a target, a rate), in
 * what suppresses them, and in what a wrong answer costs.
 */
final class RunningLowTest extends TestCase
{
    use RefreshDatabase;

    private Location $shelf;

    private StockWriter $writer;

    protected function setUp(): void
    {
        parent::setUp();

        $this->signIn('Birinci');

        $this->shelf = Location::create(['name' => 'Kiler']);
        $this->writer = new StockWriter(new StockLedger);
    }

    private function signIn(string $team): User
    {
        /** @var User $user */
        $user = User::factory()->createOne(['locale' => 'en']);
        $team = Team::create(['name' => $team, 'user_id' => $user->getKey()]);
        $user->forceFill(['current_team_id' => $team->getKey()])->save();
        $user->refresh();

        $this->actingAs($user, 'sanctum');

        return $user;
    }

    /** @param array<string, mixed> $attributes */
    private function product(string $name, array $attributes = []): Product
    {
        return Product::create(array_merge(['name' => $name, 'base_unit' => 'C62'], $attributes));
    }

    /**
     * The names the endpoint returns, in the order it returns them.
     *
     * @return list<string>
     */
    private function names(): array
    {
        $response = $this->getJson('/api/v1/running-low');

        $response->assertOk();

        return array_map(
            static fn (array $row): string => $row['name'],
            $response->json('data'),
        );
    }

    /**
     * Buy and consume `$amount` `$daysAgo` days ago.
     *
     * **The receipt is backdated too, and leaving it at today is what made the first version of the
     * rhythm test wrong.** Every purchase landing on one day gives the tenant no gap to measure, so
     * `RestockRhythm` correctly answered with its default and the test read as a broken reorder
     * point. A tenant who shops every three days has purchases three days apart; that is the shape
     * the fixture has to build.
     */
    private function demand(Product $product, float $amount, int $daysAgo): void
    {
        $this->writer->receive(
            $product,
            $this->shelf,
            $amount,
            context: new MovementContext(Carbon::today()->subDays($daysAgo)),
        );

        $this->writer->consume(
            $product,
            $this->shelf,
            $amount,
            context: new MovementContext(Carbon::today()->subDays($daysAgo)),
        );
    }

    public function test_a_product_with_nothing_on_hand_is_short_even_with_no_target(): void
    {
        // The arm that matters most today: the creation form deliberately does not ask for a target,
        // so every real product has none, and without this the screen would be empty for everybody.
        $gone = $this->product('Kıyma');
        $this->writer->receive($gone, $this->shelf, 2);
        $this->writer->consume($gone, $this->shelf, 2);

        $this->assertSame(['Kıyma'], $this->names());
    }

    public function test_a_product_that_was_never_stocked_is_short_too(): void
    {
        // No `product_stock` row at all rather than a row reading zero. Never stocked and fully
        // consumed are the same answer to "how much is there", and a left join is what makes them
        // one case instead of two.
        $this->product('Tuz');

        $this->assertSame(['Tuz'], $this->names());
    }

    public function test_a_product_with_stock_and_no_target_is_not_short(): void
    {
        // The other side of the first test, and the reason the out-of-stock arm ignores the target
        // rather than the whole screen doing so: without a target there is no answer to "how much
        // should be here", so anything above zero is not short of anything.
        $stocked = $this->product('Vida');
        $this->writer->receive($stocked, $this->shelf, 2);

        $this->assertSame([], $this->names());
    }

    public function test_at_the_target_exactly_is_not_short(): void
    {
        // **The boundary, and the shopping list is what decides it.** `forecasting.md` computes how
        // much to buy as the target minus what is on hand, so a product sitting at exactly its
        // target produces a line reading "buy 0", and running low is a strict subset of that list.
        // Two of a target of two is the amount the user asked to keep.
        //
        // Three surfaces used `<=` and now all three use `<`: this query, `ProductListQuery`'s
        // `below_par` axis and `ProductListItem.isBelowPar`.
        $atTarget = $this->product('Çekiç', ['par_level' => 2]);
        $this->writer->receive($atTarget, $this->shelf, 2);

        $below = $this->product('Tornavida', ['par_level' => 2]);
        $this->writer->receive($below, $this->shelf, 1);

        $this->assertSame(['Tornavida'], $this->names());
    }

    public function test_the_reorder_point_is_the_rate_times_the_tenants_shopping_rhythm(): void
    {
        // **The working, so the threshold can be checked with a calculator.**
        //
        // Ten demands of 2 units every 3 days: size stays 2, interval stays 3, so SBA answers
        // `0.95 * 2 / 3` = 0.633333 units a day. Purchases land on those same ten days, three days
        // apart, so the rhythm is 3 and the reorder point is `0.633333 * 3` = 1.9 units.
        //
        // 1.5 on hand is below it and 3 is above it, which is the pair that makes the assertion
        // about the threshold rather than about the sign of the number.
        $low = $this->product('Süt');
        $high = $this->product('Ayran');

        foreach (range(1, 10) as $i) {
            $this->demand($low, 2, $i * 3);
            $this->demand($high, 2, $i * 3);
        }

        $this->writer->receive($low, $this->shelf, 1.5);
        $this->writer->receive($high, $this->shelf, 3);

        $this->assertSame(['Süt'], $this->names());
    }

    public function test_a_tenant_with_no_purchase_rhythm_falls_back_to_a_week(): void
    {
        // Every purchase on ONE day, so there is no gap to measure and the default applies. At
        // 0.633333 a day a week is 4.43 units, so 4 is short and 5 is not: the pair straddles the
        // default rather than testing that something appeared.
        $low = $this->product('Süt');
        $high = $this->product('Ayran');

        foreach ([$low, $high] as $product) {
            foreach (range(1, 10) as $i) {
                // Received today, consumed in the past, so the demand series has its own rhythm and
                // the purchase series has none.
                $this->writer->receive($product, $this->shelf, 2);
                $this->writer->consume(
                    $product,
                    $this->shelf,
                    2,
                    context: new MovementContext(Carbon::today()->subDays($i * 3)),
                );
            }
        }

        $this->assertSame(7, RestockRhythm::DEFAULT_DAYS);

        $this->writer->receive($low, $this->shelf, 4);
        $this->writer->receive($high, $this->shelf, 5);

        $this->assertSame(['Süt'], $this->names());
    }

    public function test_an_abandoned_product_drops_off_but_one_with_a_target_does_not(): void
    {
        // `forecasting.md`'s sixth criterion, and the line this implementation draws through it. An
        // inferred threshold expires with the rhythm it was inferred from; a target the user typed
        // is an instruction, and dropping it silently would be an inference overriding a person.
        $abandoned = $this->product('Kinoa');
        $targeted = $this->product('Bulgur', ['par_level' => 5]);

        foreach (range(0, 9) as $i) {
            // Last demand 40 days ago on a 2-day rhythm: far past three intervals.
            $this->demand($abandoned, 1, 40 + $i * 2);
            $this->demand($targeted, 1, 40 + $i * 2);
        }

        $this->writer->receive($abandoned, $this->shelf, 1);
        $this->writer->receive($targeted, $this->shelf, 1);

        $this->assertSame(['Bulgur'], $this->names());
    }

    public function test_the_emptiest_relative_to_its_target_comes_first(): void
    {
        // As a FRACTION of what the product should hold, not as an absolute shortfall. Two of a
        // target of twenty is more urgent than two of a target of three, and the raw difference
        // would rank the bulk item above the staple every time.
        $tenth = $this->product('Un', ['par_level' => 20]);
        $this->writer->receive($tenth, $this->shelf, 2);

        $twoThirds = $this->product('Şeker', ['par_level' => 3]);
        $this->writer->receive($twoThirds, $this->shelf, 2);

        $this->assertSame(['Un', 'Şeker'], $this->names());
    }

    public function test_nothing_on_hand_outranks_everything_and_ties_break_on_the_name(): void
    {
        $low = $this->product('Un', ['par_level' => 20]);
        $this->writer->receive($low, $this->shelf, 2);

        $this->product('Zeytin');
        $this->product('Armut');

        $this->assertSame(['Armut', 'Zeytin', 'Un'], $this->names());
    }

    public function test_the_payload_carries_the_tier_and_the_cover_the_screen_groups_by(): void
    {
        $product = $this->product('Süt');

        foreach (range(1, 10) as $i) {
            $this->demand($product, 2, $i * 3);
        }

        $this->writer->receive($product, $this->shelf, 1.5);

        $row = $this->getJson('/api/v1/running-low')->assertOk()->json('data.0');

        $this->assertSame('forecast', $row['forecast']['tier']);
        $this->assertSame(10, $row['forecast']['movement_count']);
        // 1.5 units at 0.633333 a day is 2.37 days.
        $this->assertEqualsWithDelta(2.37, $row['forecast']['days_of_cover'], 0.01);
        // The threshold itself travels, so the screen can say what it is short OF.
        $this->assertEqualsWithDelta(1.9, $row['inferred_reorder_point'], 0.01);
    }

    public function test_a_product_below_the_bar_with_no_history_says_so_rather_than_guessing(): void
    {
        // The bottom tier, which is where every product starts. No forecast row exists at all, so
        // the payload carries null and the screen has nothing it could print a number from.
        $product = $this->product('Tornavida', ['par_level' => 2]);
        $this->writer->receive($product, $this->shelf, 1);

        $row = $this->getJson('/api/v1/running-low')->assertOk()->json('data.0');

        $this->assertNull($row['forecast']);
        $this->assertArrayNotHasKey('inferred_reorder_point', $row);
    }

    public function test_another_tenants_shortages_are_invisible(): void
    {
        $mine = $this->product('Süt', ['par_level' => 5]);
        $this->writer->receive($mine, $this->shelf, 1);

        $this->signIn('İkinci');

        $this->assertSame([], $this->names());
    }
}
