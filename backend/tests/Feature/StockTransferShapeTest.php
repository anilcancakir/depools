<?php

namespace Tests\Feature;

use App\Models\Location;
use App\Models\Product;
use App\Models\Team;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * `transfer`'s own shape, pinned before the FormRequest extraction (backend form-request
 * conformance, step 3) moves its rules into `TransferStockRequest`, so a wrongly shared base with
 * `receive`/`consume` is caught by the suite instead of by a client.
 *
 * ### Why not the plan's literal "REJECTS a payload carrying location_id"
 *
 * Laravel does not reject unknown keys: `validate()`, and a FormRequest's `validated()` the same way,
 * return only the keys the rule array names and silently drop anything else. An extra `location_id`
 * on a transfer payload is DROPPED today, not refused, so a test asserting 422 for it would fail
 * against correct code. The regression a wrongly shared base would actually cause is `location_id`
 * becoming REQUIRED, inherited from the receive/consume base, which would turn today's six-field
 * transfer payload into a 422. That is what the first test below pins, and the third documents the
 * silent-drop behaviour the plan's phrasing guessed at instead.
 */
final class StockTransferShapeTest extends TestCase
{
    use RefreshDatabase;

    /** @return array{0: Location, 1: Location, 2: Product} */
    private function tenantWithStock(): array
    {
        /** @var User $user */
        $user = User::factory()->createOne();
        $team = Team::create(['name' => 'Transfer Shape', 'user_id' => $user->getKey()]);
        $user->forceFill(['current_team_id' => $team->getKey()])->save();
        $this->actingAs($user->refresh(), 'sanctum');

        $from = Location::create(['name' => 'Mutfak']);
        $to = Location::create(['name' => 'Depo']);
        $product = Product::create(['name' => 'Süt', 'base_unit' => 'C62']);

        $this->postJson('/api/v1/stock/receive', [
            'product_id' => $product->getKey(),
            'location_id' => $from->getKey(),
            'quantity' => 10,
        ])->assertCreated();

        return [$from, $to, $product];
    }

    public function test_a_transfer_succeeds_with_no_location_id_in_the_payload(): void
    {
        [$from, $to, $product] = $this->tenantWithStock();

        // The six fields `transfer` actually names. No `location_id`: this is exactly what breaks
        // the moment `transfer` inherits the receive/consume base, where `location_id` is `required`.
        $this->postJson('/api/v1/stock/transfer', [
            'product_id' => $product->getKey(),
            'from_location_id' => $from->getKey(),
            'to_location_id' => $to->getKey(),
            'quantity' => 4,
        ])->assertCreated();
    }

    public function test_a_transfer_refuses_the_same_location_at_both_ends(): void
    {
        [$from, , $product] = $this->tenantWithStock();

        $this->postJson('/api/v1/stock/transfer', [
            'product_id' => $product->getKey(),
            'from_location_id' => $from->getKey(),
            'to_location_id' => $from->getKey(),
            'quantity' => 4,
        ])->assertStatus(422)->assertJsonValidationErrors('to_location_id');
    }

    public function test_a_transfer_ignores_an_extra_location_id_and_still_moves_the_pair(): void
    {
        [$from, $to, $product] = $this->tenantWithStock();

        // `location_id` is not one of `transfer`'s six fields, so an extra one arriving on the
        // payload is silently ignored rather than refused. The total stays put (a transfer moves
        // stock, it does not create or destroy it) and the pair still writes against `from`/`to`.
        $this->postJson('/api/v1/stock/transfer', [
            'product_id' => $product->getKey(),
            'from_location_id' => $from->getKey(),
            'to_location_id' => $to->getKey(),
            'location_id' => $from->getKey(),
            'quantity' => 4,
        ])->assertCreated()->assertJsonCount(2, 'data.movement_ids');

        $this->getJson('/api/v1/products/'.$product->getKey())
            ->assertOk()
            ->assertJsonPath('data.quantity', '10.000');
    }
}
