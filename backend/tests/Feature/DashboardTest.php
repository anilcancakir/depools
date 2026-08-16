<?php

namespace Tests\Feature;

use App\Models\Location;
use App\Models\Product;
use App\Models\Team;
use App\Models\User;
use App\Services\StockLedger;
use App\Services\StockWriter;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Testing\TestResponse;
use Tests\TestCase;

/**
 * The landing screen's one request.
 *
 * The assertions worth having are the ones about the seam between a COUNTER and the list beside it:
 * the screen's own docblock says no figure on it may disagree with the page it links to, and the
 * only way that holds is if the count is the whole set while the rows are the first few.
 */
final class DashboardTest extends TestCase
{
    use RefreshDatabase;

    private Location $shelf;

    private StockWriter $writer;

    protected function setUp(): void
    {
        parent::setUp();

        /** @var User $user */
        $user = User::factory()->createOne(['locale' => 'en']);
        $team = Team::create(['name' => 'Alpha', 'user_id' => $user->getKey()]);
        $user->forceFill(['current_team_id' => $team->getKey()])->save();

        $this->actingAs($user->refresh(), 'sanctum');

        $this->shelf = Location::create(['name' => 'Fridge']);
        $this->writer = new StockWriter(new StockLedger);
    }

    private function product(string $name, ?float $parLevel = null): Product
    {
        return Product::create([
            'name' => $name,
            'base_unit' => 'C62',
            'tracks_expiry' => true,
            'par_level' => $parLevel,
        ]);
    }

    private function dashboard(): TestResponse
    {
        return $this->getJson('/api/v1/dashboard');
    }

    public function test_a_tenant_with_no_stock_is_told_so_rather_than_shown_zeros(): void
    {
        // **The flag that decides which SCREEN they get.** A fresh tenant sees the setup steps, not a
        // thinner dashboard: the counters, the four cards and the history all describe stock, so
        // every one of them would render as a zero. Six ways of saying the same nothing.
        $this->product('Süt');

        $this->dashboard()->assertOk()->assertJsonPath('data.has_stock', false);
    }

    public function test_stock_anywhere_flips_it(): void
    {
        $milk = $this->product('Süt');

        $this->writer->receive($milk, $this->shelf, 2);

        $this->dashboard()->assertOk()->assertJsonPath('data.has_stock', true);
    }

    public function test_the_subtitle_counts_what_the_tenant_has(): void
    {
        $this->product('Süt');
        $this->product('Ekmek');
        Location::create(['name' => 'Pantry']);

        $this->dashboard()->assertOk()
            ->assertJsonPath('data.products', 2)
            // The shelf from setUp plus the one above.
            ->assertJsonPath('data.locations', 2);
    }

    public function test_a_lot_past_its_date_counts_as_expired_and_not_as_approaching(): void
    {
        // The two counters split one query, and the boundary is today: a date that has passed cannot
        // be recovered and a date approaching still can, which is the whole reason they are separate
        // cards.
        $cheese = $this->product('Peynir');

        $this->writer->receive($cheese, $this->shelf, 1, expiresAt: now()->subDay()->toDateString());
        $this->writer->receive($cheese, $this->shelf, 1, expiresAt: now()->addDays(2)->toDateString());

        $this->dashboard()->assertOk()
            ->assertJsonPath('data.counters.expired', 1)
            ->assertJsonPath('data.counters.approaching', 1)
            ->assertJsonCount(1, 'data.expired')
            ->assertJsonCount(1, 'data.approaching');
    }

    public function test_a_lot_beyond_the_horizon_counts_as_neither(): void
    {
        $flour = $this->product('Un');

        $this->writer->receive($flour, $this->shelf, 1, expiresAt: now()->addDays(60)->toDateString());

        $this->dashboard()->assertOk()
            ->assertJsonPath('data.counters.expired', 0)
            ->assertJsonPath('data.counters.approaching', 0);
    }

    public function test_out_of_stock_and_below_target_are_different_questions(): void
    {
        // Out of stock is a lost sale today; below target is a decision for this week. A product
        // holding nothing is NOT below target, which is what the filter's own null-and-zero guards
        // are for, so the two counters must not double-count it.
        $gone = $this->product('Kıyma', parLevel: 1);
        $low = $this->product('Süt', parLevel: 4);

        $this->writer->receive($gone, $this->shelf, 1);
        $this->writer->consume($gone, $this->shelf, 1);
        $this->writer->receive($low, $this->shelf, 2);

        $this->dashboard()->assertOk()
            ->assertJsonPath('data.counters.out_of_stock', 1)
            ->assertJsonPath('data.counters.below_target', 1)
            ->assertJsonPath('data.out_of_stock.0.name', 'Kıyma')
            ->assertJsonPath('data.below_target.0.name', 'Süt');
    }

    public function test_a_product_with_no_target_is_never_below_one(): void
    {
        // "Below target" has to mean something somebody decided, or every product holding a little
        // reports as running low and the card becomes noise.
        $milk = $this->product('Süt');

        $this->writer->receive($milk, $this->shelf, 1);

        $this->dashboard()->assertOk()->assertJsonPath('data.counters.below_target', 0);
    }

    public function test_the_counter_is_the_whole_set_while_the_rows_are_the_first_few(): void
    {
        // **The seam the screen's docblock is about.** Counting the previewed rows would make every
        // card say "3" however many products are actually short, and the card's whole sentence is
        // "3 of 47".
        for ($i = 0; $i < 5; $i++) {
            $product = $this->product("Ürün {$i}", parLevel: 1);

            $this->writer->receive($product, $this->shelf, 1);
            $this->writer->consume($product, $this->shelf, 1);
        }

        $this->dashboard()->assertOk()
            ->assertJsonPath('data.counters.out_of_stock', 5)
            ->assertJsonCount(3, 'data.out_of_stock');
    }

    public function test_the_activity_feed_spans_products_rather_than_one(): void
    {
        // The one thing here no endpoint answered: `/products/{id}/movements` is per product, and a
        // dashboard has no product to hang off.
        $milk = $this->product('Süt');
        $bread = $this->product('Ekmek');

        $this->writer->receive($milk, $this->shelf, 1);
        $this->writer->receive($bread, $this->shelf, 1);

        $names = array_column(
            $this->dashboard()->assertOk()->json('data.activity'),
            'product_name',
        );

        $this->assertEqualsCanonicalizing(['Süt', 'Ekmek'], $names);
    }

    public function test_the_activity_feed_is_ordered_by_when_it_happened(): void
    {
        // Not by write time, for the reason the model states: a receipt entered on Tuesday for a
        // Sunday shop belongs where it happened. Written in the backwards order so the two sorts
        // disagree, which is the only arrangement that can fail for the right reason.
        $milk = $this->product('Süt');

        $this->postJson('/api/v1/stock/receive', [
            'product_id' => $milk->getKey(),
            'location_id' => $this->shelf->getKey(),
            'quantity' => 9,
        ])->assertCreated();

        $this->postJson('/api/v1/stock/receive', [
            'product_id' => $milk->getKey(),
            'location_id' => $this->shelf->getKey(),
            'quantity' => 1,
            'occurred_at' => now()->subDays(5)->toIso8601String(),
        ])->assertCreated();

        $deltas = array_map(
            static fn (array $row): float => (float) $row['delta'],
            $this->dashboard()->assertOk()->json('data.activity'),
        );

        $this->assertSame([9.0, 1.0], $deltas);
    }

    public function test_another_tenants_stock_is_not_on_this_dashboard(): void
    {
        $mine = $this->product('Süt');
        $this->writer->receive($mine, $this->shelf, 1, expiresAt: now()->addDay()->toDateString());

        /** @var User $other */
        $other = User::factory()->createOne();
        $team = Team::create(['name' => 'Beta', 'user_id' => $other->getKey()]);
        $other->forceFill(['current_team_id' => $team->getKey()])->save();
        $this->actingAs($other->refresh(), 'sanctum');

        $this->dashboard()->assertOk()
            ->assertJsonPath('data.has_stock', false)
            ->assertJsonPath('data.products', 0)
            ->assertJsonPath('data.counters.approaching', 0)
            ->assertJsonCount(0, 'data.activity');
    }

    public function test_it_is_behind_the_session_like_everything_else(): void
    {
        $this->app->get('auth')->forgetGuards();

        $this->getJson('/api/v1/dashboard')->assertUnauthorized();
    }
}
