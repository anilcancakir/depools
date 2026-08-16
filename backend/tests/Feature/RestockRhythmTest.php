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
 * How often this tenant shops, which is the lead time a reorder point is multiplied by (D48).
 */
final class RestockRhythmTest extends TestCase
{
    use RefreshDatabase;

    private Location $shelf;

    private StockWriter $writer;

    private RestockRhythm $rhythm;

    private string $teamId;

    protected function setUp(): void
    {
        parent::setUp();

        /** @var User $user */
        $user = User::factory()->createOne(['locale' => 'en']);
        $team = Team::create(['name' => 'Alpha', 'user_id' => $user->getKey()]);
        $user->forceFill(['current_team_id' => $team->getKey()])->save();

        $this->actingAs($user->refresh(), 'sanctum');

        $this->teamId = (string) $team->getKey();
        $this->shelf = Location::create(['name' => 'Kiler']);
        $this->writer = new StockWriter(new StockLedger);
        $this->rhythm = new RestockRhythm;
    }

    private function buy(Product $product, int $daysAgo): void
    {
        $this->writer->receive(
            $product,
            $this->shelf,
            1,
            context: new MovementContext(Carbon::today()->subDays($daysAgo)),
        );
    }

    private function product(string $name): Product
    {
        return Product::create(['name' => $name, 'base_unit' => 'C62']);
    }

    public function test_a_tenant_who_has_never_bought_anything_gets_the_default(): void
    {
        $this->assertSame(RestockRhythm::DEFAULT_DAYS, $this->rhythm->forTeam($this->teamId));
    }

    public function test_one_shopping_day_is_still_the_default(): void
    {
        // One day is a fact about one day. A gap needs two, which is the same rule the forecast's own
        // interval follows: the SECOND demand is what seeds it.
        $this->buy($this->product('Süt'), 3);

        $this->assertSame(RestockRhythm::DEFAULT_DAYS, $this->rhythm->forTeam($this->teamId));
    }

    public function test_the_rhythm_is_the_mean_gap_between_shopping_days(): void
    {
        // Four days spanning 21, which is three gaps of seven.
        foreach ([21, 14, 7, 0] as $daysAgo) {
            $this->buy($this->product('Ürün '.$daysAgo), $daysAgo);
        }

        $this->assertSame(7, $this->rhythm->forTeam($this->teamId));
    }

    public function test_a_trolley_is_one_trip_however_many_things_are_in_it(): void
    {
        // **The property this whole class turns on.** One shopping trip writes a purchase movement
        // per item, so counting MOVEMENTS would answer that this tenant restocks several times an
        // hour and every reorder point would collapse to nothing.
        //
        // Two trips fourteen days apart, five items each. By days the answer is 14; by movements it
        // would be 14 / 9, which rounds to 2.
        foreach ([14, 0] as $daysAgo) {
            foreach (range(1, 5) as $i) {
                $this->buy($this->product("Ürün {$daysAgo}-{$i}"), $daysAgo);
            }
        }

        $this->assertSame(14, $this->rhythm->forTeam($this->teamId));
    }

    public function test_a_fractional_rhythm_rounds_up(): void
    {
        // Three days spanning 5: two gaps averaging 2.5. Rounded up, because the rhythm decides how
        // early to warn and half a day rounded down is half a day of warning given away.
        foreach ([5, 3, 0] as $daysAgo) {
            $this->buy($this->product('Ürün '.$daysAgo), $daysAgo);
        }

        $this->assertSame(3, $this->rhythm->forTeam($this->teamId));
    }

    public function test_an_imported_year_of_history_cannot_stretch_the_rhythm_past_the_cap(): void
    {
        // The failure the cap exists for: a tenant who back-filled a year in one sitting and then
        // made one real purchase has a mean gap of months, and an uncapped rhythm would put every
        // product they own on the shopping list at once.
        $this->buy($this->product('Eski'), 360);
        $this->buy($this->product('Yeni'), 0);

        $this->assertSame(RestockRhythm::MAX_DAYS, $this->rhythm->forTeam($this->teamId));
    }

    public function test_a_habit_that_changed_is_eventually_forgotten(): void
    {
        // Outside the window, so it does not drag the mean. Without the horizon this tenant's two
        // recent weekly trips would be averaged against a purchase from two years ago.
        $this->buy($this->product('Çok eski'), 800);
        $this->buy($this->product('Süt'), 7);
        $this->buy($this->product('Ekmek'), 0);

        $this->assertSame(7, $this->rhythm->forTeam($this->teamId));
    }

    public function test_only_purchases_count_as_a_shopping_trip(): void
    {
        // A count, a transfer and a consumption are not trips to a shop. Two purchases fourteen days
        // apart with consumption in between still reads as fortnightly.
        $product = $this->product('Süt');

        $this->buy($product, 14);

        $this->writer->consume(
            $product,
            $this->shelf,
            1,
            context: new MovementContext(Carbon::today()->subDays(7)),
        );

        $this->buy($product, 0);

        $this->assertSame(14, $this->rhythm->forTeam($this->teamId));
    }

    public function test_another_tenants_shopping_is_not_this_tenants_rhythm(): void
    {
        /** @var User $other */
        $other = User::factory()->createOne(['locale' => 'en']);
        $otherTeam = Team::create(['name' => 'Beta', 'user_id' => $other->getKey()]);

        $this->buy($this->product('Süt'), 2);
        $this->buy($this->product('Ekmek'), 0);

        $this->assertSame(2, $this->rhythm->forTeam($this->teamId));
        $this->assertSame(
            RestockRhythm::DEFAULT_DAYS,
            $this->rhythm->forTeam((string) $otherTeam->getKey()),
        );
    }
}
