<?php

namespace Tests\Feature;

use App\Models\Location;
use App\Models\Product;
use App\Models\ProductSerial;
use App\Models\Team;
use App\Models\User;
use App\Services\StockLedger;
use App\Services\StockWriter;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Testing\TestResponse;
use Tests\TestCase;

/**
 * What is running out of time.
 *
 * The interesting assertions are the ones about which DATE binds, because that is the whole reason
 * this cannot be a `where expires_at <= ?`: an opened carton's real deadline is shorter than the one
 * printed on it, and it is computed in PHP.
 */
final class ExpiringTest extends TestCase
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

    private function product(string $name, ?int $openedShelfLife = null): Product
    {
        return Product::create([
            'name' => $name,
            'base_unit' => 'C62',
            'tracks_expiry' => true,
            'opened_shelf_life_days' => $openedShelfLife,
        ]);
    }

    private function expiring(int $horizon = 7): TestResponse
    {
        return $this->getJson('/api/v1/expiring?horizon='.$horizon);
    }

    public function test_a_lot_inside_the_horizon_is_listed_with_what_it_belongs_to(): void
    {
        $milk = $this->product('Süt');

        $this->writer->receive($milk, $this->shelf, 3, expiresAt: now()->addDays(2)->toDateString());

        $row = $this->expiring()->assertOk()->json('data.0');

        $this->assertSame('lot', $row['kind']);
        $this->assertSame('Süt', $row['product_name']);
        $this->assertSame('Fridge', $row['location_name']);
        $this->assertSame(now()->addDays(2)->toDateString(), $row['binding_date']);
        $this->assertFalse($row['is_open']);
    }

    public function test_a_lot_beyond_the_horizon_is_not(): void
    {
        $flour = $this->product('Un');

        $this->writer->receive($flour, $this->shelf, 1, expiresAt: now()->addDays(60)->toDateString());

        $this->expiring()->assertOk()->assertJsonCount(0, 'data');
    }

    public function test_the_horizon_is_the_callers_and_seven_is_only_the_default(): void
    {
        $flour = $this->product('Un');

        $this->writer->receive($flour, $this->shelf, 1, expiresAt: now()->addDays(60)->toDateString());

        $this->expiring()->assertJsonCount(0, 'data');
        $this->expiring(horizon: 90)->assertJsonCount(1, 'data');
    }

    public function test_an_opened_lot_binds_to_its_shorter_deadline(): void
    {
        // **The case that makes this more than a `where` clause.** The carton is printed for next
        // year and was opened yesterday with a three-day shelf life, so it has two days left. SQL
        // cannot see that: `expires_at` is nowhere near the horizon.
        $milk = $this->product('Süt', openedShelfLife: 3);

        $this->writer->receive($milk, $this->shelf, 2, expiresAt: now()->addYear()->toDateString());
        $this->writer->consume($milk, $this->shelf, 0.5);

        $row = $this->expiring()->assertOk()->json('data.0');

        $this->assertTrue($row['is_open']);
        $this->assertSame(now()->addDays(3)->toDateString(), $row['binding_date']);
        // **Both dates travel**, because the row has to be able to say why its deadline is what it
        // is: an opened carton printed for next year reads as wrong without them.
        $this->assertSame(now()->addYear()->toDateString(), $row['expires_at']);
        $this->assertSame(now()->toDateString(), $row['opened_at']);
    }

    public function test_an_opened_lot_with_no_shelf_life_keeps_its_printed_date(): void
    {
        // Opening is not a deadline by itself. A product with no `opened_shelf_life_days` has nothing
        // to shorten to, so a candidate row the SQL pulled in for being open drops out in PHP.
        $jar = $this->product('Reçel');

        $this->writer->receive($jar, $this->shelf, 2, expiresAt: now()->addDays(60)->toDateString());
        $this->writer->consume($jar, $this->shelf, 0.5);

        $this->expiring()->assertOk()->assertJsonCount(0, 'data');
    }

    public function test_a_lot_already_past_its_date_is_listed(): void
    {
        // The list is a queue of things to deal with, and something that went off yesterday is the
        // most urgent thing on it rather than history.
        $cheese = $this->product('Peynir');

        $this->writer->receive($cheese, $this->shelf, 1, expiresAt: now()->subDay()->toDateString());

        $this->expiring()->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.binding_date', now()->subDay()->toDateString());
    }

    public function test_a_depleted_lot_is_history_rather_than_a_task(): void
    {
        // Nothing is left to save, so a row for it would be a job the user cannot do.
        $milk = $this->product('Süt');

        $this->writer->receive($milk, $this->shelf, 2, expiresAt: now()->addDay()->toDateString());
        $this->writer->consume($milk, $this->shelf, 2);

        $this->expiring()->assertOk()->assertJsonCount(0, 'data');
    }

    public function test_one_row_per_lot_rather_than_per_product(): void
    {
        // A carton expiring tomorrow and one expiring in a week are two different decisions, and a
        // row per product would say something needs using without saying which one to reach for.
        $milk = $this->product('Süt');

        $this->writer->receive($milk, $this->shelf, 1, expiresAt: now()->addDay()->toDateString());
        $this->writer->receive($milk, $this->shelf, 1, expiresAt: now()->addDays(5)->toDateString());

        $this->expiring()->assertOk()->assertJsonCount(2, 'data');
    }

    public function test_a_warranty_sits_in_the_same_list(): void
    {
        // Depools is not a pantry app. A warranty ending in two days belongs beside a cheese that
        // went off yesterday, and a list carrying only food would bake the food assumption in again.
        $drill = $this->product('Matkap');

        ProductSerial::create([
            'product_id' => $drill->getKey(),
            'location_id' => $this->shelf->getKey(),
            'serial' => 'SN-1',
            'acquired_at' => now()->subMonth(),
            'warranty_ends_at' => now()->addDays(2)->toDateString(),
        ]);

        $row = $this->expiring()->assertOk()->json('data.0');

        $this->assertSame('warranty', $row['kind']);
        $this->assertSame('Matkap', $row['product_name']);
        $this->assertSame('SN-1', $row['lot_code']);
        $this->assertSame('1.000', $row['quantity']);
    }

    public function test_a_released_serial_is_no_longer_the_tenants_problem(): void
    {
        $drill = $this->product('Matkap');

        ProductSerial::create([
            'product_id' => $drill->getKey(),
            'location_id' => $this->shelf->getKey(),
            'serial' => 'SN-2',
            'acquired_at' => now()->subMonth(),
            'warranty_ends_at' => now()->addDays(2)->toDateString(),
            'released_at' => now()->subDay(),
        ]);

        $this->expiring()->assertOk()->assertJsonCount(0, 'data');
    }

    public function test_the_list_is_ordered_by_the_date_rather_than_by_its_table(): void
    {
        // The two halves come from two queries, and the screen is one queue.
        $cheese = $this->product('Peynir');
        $drill = $this->product('Matkap');

        $this->writer->receive($cheese, $this->shelf, 1, expiresAt: now()->addDays(5)->toDateString());

        ProductSerial::create([
            'product_id' => $drill->getKey(),
            'location_id' => $this->shelf->getKey(),
            'serial' => 'SN-3',
            'acquired_at' => now()->subMonth(),
            'warranty_ends_at' => now()->addDay()->toDateString(),
        ]);

        $kinds = array_column($this->expiring()->assertOk()->json('data'), 'kind');

        $this->assertSame(['warranty', 'lot'], $kinds);
    }

    public function test_another_tenants_lot_is_not_in_this_tenants_list(): void
    {
        // Written before the feature it protects, per the backend rules. `TeamScope` does it in the
        // query rather than after it, so this is about the scope being reachable from both halves.
        $mine = $this->product('Süt');
        $this->writer->receive($mine, $this->shelf, 1, expiresAt: now()->addDay()->toDateString());

        /** @var User $other */
        $other = User::factory()->createOne();
        $team = Team::create(['name' => 'Beta', 'user_id' => $other->getKey()]);
        $other->forceFill(['current_team_id' => $team->getKey()])->save();
        $this->actingAs($other->refresh(), 'sanctum');

        $this->expiring()->assertOk()->assertJsonCount(0, 'data');
    }

    public function test_a_horizon_beyond_the_cap_is_refused(): void
    {
        // An unbounded horizon is a way to ask for every lot the tenant has ever held in one request.
        $this->getJson('/api/v1/expiring?horizon=4000')
            ->assertStatus(422)
            ->assertJsonValidationErrors('horizon');
    }
}
