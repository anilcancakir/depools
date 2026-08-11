<?php

namespace Tests\Feature;

use App\Enums\MovementReason;
use App\Models\Location;
use App\Models\Product;
use App\Models\StockMovement;
use App\Models\Team;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * The `api/v1` contract, and tenancy rule 2 at the level where it is actually observable.
 *
 * The model-level tests already prove another tenant's row is not found. This file proves the
 * consequence a client can see: the response is 404 and never 403. That distinction is the whole
 * rule, because a 403 confirms the identifier is real, and an attacker holding a range of ids can
 * map another tenant's catalog one request at a time without ever reading a row.
 */
final class InventoryApiTest extends TestCase
{
    use RefreshDatabase;

    /** @return array{0: User, 1: Location, 2: Product} */
    private function tenant(string $name): array
    {
        $user = User::factory()->create();
        $team = Team::create(['name' => $name, 'user_id' => $user->getKey()]);
        $user->forceFill(['current_team_id' => $team->getKey()])->save();

        $this->actingAs($user->refresh(), 'sanctum');

        $location = Location::create(['name' => $name.' Mutfak']);
        $product = Product::create(['name' => $name.' Süt', 'base_unit' => 'adet']);

        return [$user->refresh(), $location, $product];
    }

    public function test_the_endpoints_require_authentication(): void
    {
        // Not only an auth concern: without a user the tenant scope resolves to null and the list
        // would come back EMPTY rather than leaking, which looks like a broken feature instead of
        // a missing guard. The guard is still required, and this asserts it exists.
        $this->getJson('/api/v1/products')->assertUnauthorized();
        $this->postJson('/api/v1/stock/receive')->assertUnauthorized();
    }

    public function test_a_cross_tenant_read_is_404_and_never_403(): void
    {
        [, , $theirs] = $this->tenant('İkinci');
        $this->tenant('Birinci');

        $response = $this->getJson('/api/v1/products/'.$theirs->getKey());

        $response->assertNotFound();
        $this->assertNotSame(403, $response->status());
    }

    public function test_a_cross_tenant_write_target_is_404_too(): void
    {
        [, $theirLocation, $theirProduct] = $this->tenant('İkinci');
        $this->tenant('Birinci');

        // The attacker holds both identifiers and is authenticated as themselves. The write path
        // resolves through the same scoped models as the read path, so it answers identically.
        $this->postJson('/api/v1/stock/receive', [
            'product_id' => $theirProduct->getKey(),
            'location_id' => $theirLocation->getKey(),
            'quantity' => 5,
        ])->assertNotFound();
    }

    public function test_a_list_contains_only_the_callers_own_rows(): void
    {
        $this->tenant('İkinci');
        [, , $mine] = $this->tenant('Birinci');

        $this->getJson('/api/v1/products')
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.id', $mine->getKey());
    }

    public function test_receiving_then_reading_reports_the_quantity(): void
    {
        [, $location, $product] = $this->tenant('Birinci');

        $this->postJson('/api/v1/stock/receive', [
            'product_id' => $product->getKey(),
            'location_id' => $location->getKey(),
            'quantity' => 6,
            'expires_at' => '2026-09-01',
        ])->assertCreated();

        $this->getJson('/api/v1/products/'.$product->getKey())
            ->assertOk()
            ->assertJsonPath('data.quantity', '6.000')
            ->assertJsonPath('data.locations.0.earliest_expires_at', '2026-09-01');
    }

    public function test_the_endpoint_serves_the_tags_the_screen_renders(): void
    {
        [, , $product] = $this->tenant('Birinci');

        $product->syncTags(['kahvaltı', 'soğuk zincir']);

        // The loop the audit found open: `ProductShowView` painted these chips and no endpoint could
        // ever have sent them. Names rather than objects, because the chip renders a name and the filter
        // sends one back.
        $this->getJson('/api/v1/products/'.$product->getKey())
            ->assertOk()
            ->assertJsonPath('data.tags', ['kahvaltı', 'soğuk zincir']);
    }

    public function test_a_tenant_never_sees_another_tenants_tags(): void
    {
        [, , $mine] = $this->tenant('Birinci');
        $mine->syncTags(['kahvaltı']);

        [, , $theirs] = $this->tenant('İkinci');
        $theirs->syncTags(['kahvaltı']);

        // Two canonical rows, one per tenant, and the eager load must not cross between them. The
        // `tenant()` helper leaves the caller acting as the LAST tenant it created.
        $this->getJson('/api/v1/products/'.$theirs->getKey())
            ->assertOk()
            ->assertJsonPath('data.tags', ['kahvaltı']);

        $this->getJson('/api/v1/products/'.$mine->getKey())->assertNotFound();
    }

    public function test_taking_more_than_exists_is_422_rather_than_500(): void
    {
        [, $location, $product] = $this->tenant('Birinci');

        $this->postJson('/api/v1/stock/receive', [
            'product_id' => $product->getKey(),
            'location_id' => $location->getKey(),
            'quantity' => 2,
        ])->assertCreated();

        // A shelf that does not hold enough is a fact about the tenant's stock, not a server
        // fault, so it comes back shaped like rejected input and lands beside the field.
        $this->postJson('/api/v1/stock/consume', [
            'product_id' => $product->getKey(),
            'location_id' => $location->getKey(),
            'quantity' => 5,
        ])->assertStatus(422)->assertJsonValidationErrors('quantity');
    }

    public function test_a_transfer_writes_the_pair_and_moves_the_total(): void
    {
        [, $from, $product] = $this->tenant('Birinci');
        $to = Location::create(['name' => 'Depo']);

        $this->postJson('/api/v1/stock/receive', [
            'product_id' => $product->getKey(),
            'location_id' => $from->getKey(),
            'quantity' => 10,
        ])->assertCreated();

        $this->postJson('/api/v1/stock/transfer', [
            'product_id' => $product->getKey(),
            'from_location_id' => $from->getKey(),
            'to_location_id' => $to->getKey(),
            'quantity' => 4,
        ])->assertCreated()->assertJsonCount(2, 'data.movement_ids');

        $this->getJson('/api/v1/products/'.$product->getKey())
            ->assertOk()
            ->assertJsonPath('data.quantity', '10.000');
    }

    public function test_waste_is_recorded_under_its_own_reason(): void
    {
        [, $location, $product] = $this->tenant('Birinci');

        $this->postJson('/api/v1/stock/receive', [
            'product_id' => $product->getKey(),
            'location_id' => $location->getKey(),
            'quantity' => 5,
        ])->assertCreated();

        $this->postJson('/api/v1/stock/consume', [
            'product_id' => $product->getKey(),
            'location_id' => $location->getKey(),
            'quantity' => 2,
            'reason' => 'waste',
        ])->assertCreated();

        $this->assertSame(1, StockMovement::where('reason', MovementReason::Waste)->count());
    }

    public function test_a_sku_is_unique_within_a_tenant_and_free_across_them(): void
    {
        $this->tenant('İkinci');
        $this->postJson('/api/v1/products', ['name' => 'Un', 'base_unit' => 'kg', 'sku' => 'UN-1'])
            ->assertCreated();

        $this->tenant('Birinci');
        // The same code in another tenant is not a collision: two businesses numbering their own
        // shelves the same way is the normal case, not a conflict to resolve.
        $this->postJson('/api/v1/products', ['name' => 'Un', 'base_unit' => 'kg', 'sku' => 'UN-1'])
            ->assertCreated();

        $this->postJson('/api/v1/products', ['name' => 'Başka un', 'base_unit' => 'kg', 'sku' => 'UN-1'])
            ->assertStatus(422)->assertJsonValidationErrors('sku');
    }

    public function test_a_location_list_arrives_in_reading_order(): void
    {
        [, $root] = $this->tenant('Birinci');
        $this->postJson('/api/v1/locations', ['name' => 'Buzdolabı', 'parent_id' => $root->getKey()])
            ->assertCreated()
            ->assertJsonPath('data.depth', 1);

        $this->getJson('/api/v1/locations')
            ->assertOk()
            ->assertJsonPath('data.1.full_path', 'Birinci Mutfak › Buzdolabı');
    }
}
