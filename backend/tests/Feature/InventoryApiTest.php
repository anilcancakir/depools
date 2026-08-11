<?php

namespace Tests\Feature;

use App\Enums\MovementReason;
use App\Models\Location;
use App\Models\Product;
use App\Models\ProductSerial;
use App\Models\StockMovement;
use App\Models\Team;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
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
        /** @var User $user */
        $user = User::factory()->createOne();
        $team = Team::create(['name' => $name, 'user_id' => $user->getKey()]);
        $user->forceFill(['current_team_id' => $team->getKey()])->save();
        $user->refresh();

        $this->actingAs($user, 'sanctum');

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
        $this->postJson('/api/v1/stock/count')->assertUnauthorized();
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

    public function test_the_list_carries_every_field_a_product_row_derives_from(): void
    {
        [, $location, $product] = $this->tenant('Birinci');

        $product->fill([
            'description' => 'Tam yağlı, pastörize',
            'default_shelf_life_days' => 7,
            'opened_shelf_life_days' => 3,
            'par_level' => 6,
            'reorder_point' => 2,
        ])->save();

        $this->postJson('/api/v1/stock/receive', [
            'product_id' => $product->getKey(),
            'location_id' => $location->getKey(),
            'quantity' => 4,
            'expires_at' => '2026-09-01',
        ])->assertCreated();

        $row = $this->getJson('/api/v1/products')->assertOk()->json('data.0');

        // Each of these decides something the row RENDERS, which is why they are asserted together
        // rather than one per test: the warning window is derived per product from the shelf life, so
        // a payload missing it gives every product the neutral seven days and a five-day carton then
        // never warns in time. The opened life is the second clock (D27), the thresholds are what
        // "below par" and "reorder" compare against, and the movement count is the only thing that
        // decides whether a rate may be claimed at all.
        $this->assertSame('Tam yağlı, pastörize', $row['description']);
        $this->assertSame(7, $row['default_shelf_life_days']);
        $this->assertSame(3, $row['opened_shelf_life_days']);
        $this->assertSame('6.000', $row['par_level']);
        $this->assertSame('2.000', $row['reorder_point']);
        $this->assertSame('lot', $row['tracking_mode']);
        $this->assertArrayHasKey('product_category_id', $row);

        // One inbound movement, so `forecasting.md`'s lowest tier: the client may show the user's own
        // target and no time claim. A list that could not see this would have to speak cautiously
        // about everything or confidently about nothing.
        $this->assertSame(1, $row['movements_count']);

        // Derived, and already correct before this change: the quantity from the projection and the
        // BINDING date per location rather than the printed one.
        $this->assertSame('4.000', $row['quantity']);
        $this->assertSame('2026-09-01', $row['locations'][0]['earliest_expires_at']);
    }

    public function test_the_detail_endpoint_serves_the_lots_behind_the_total(): void
    {
        [, $location, $product] = $this->tenant('Birinci');
        $product->fill(['tracks_expiry' => true, 'opened_shelf_life_days' => 3])->save();

        // Two lots with different printed dates, which is the reason expiry belongs to a lot.
        foreach (['2026-09-20', '2026-09-10'] as $date) {
            $this->postJson('/api/v1/stock/receive', [
                'product_id' => $product->getKey(),
                'location_id' => $location->getKey(),
                'quantity' => 2,
                'expires_at' => $date,
            ])->assertCreated();
        }

        $data = $this->getJson('/api/v1/products/'.$product->getKey())->assertOk()->json('data');

        $this->assertCount(2, $data['lots'], 'The detail screen draws the batches, not the total');

        // Both dates on the wire, not one. The printed date and the date that GOVERNS are different
        // facts once a lot is opened, and the screen shows which applies; here nothing is opened, so
        // they agree, and that agreement is what the opened case has to diverge from.
        $earlier = collect($data['lots'])->firstWhere('expires_at', '2026-09-10');
        $this->assertSame('2026-09-10', $earlier['binding_expires_at']);
        $this->assertSame('2.000', $earlier['remaining_quantity']);
        $this->assertFalse($earlier['is_depleted']);

        // The list payload must NOT carry them. A fifty-row list has no room to draw a lot and every
        // row would be shipping its whole ledger.
        $row = $this->getJson('/api/v1/products')->assertOk()->json('data.0');
        $this->assertArrayNotHasKey('lots', $row);
        $this->assertArrayNotHasKey('serials', $row);
    }

    public function test_a_serial_tracked_product_serves_units_rather_than_lots(): void
    {
        [, $location, $product] = $this->tenant('Birinci');
        $product->fill(['tracking_mode' => 'serial'])->save();

        // Created directly, because there is no write path for a serial yet and the read side is
        // what this pins. `StockWriter::receive` refuses a serial product on purpose.
        ProductSerial::create([
            'product_id' => $product->getKey(),
            'location_id' => $location->getKey(),
            'serial' => 'MK-DHP484-002391',
            'warranty_ends_at' => '2027-02-12',
            'acquired_at' => '2026-02-12',
        ]);

        $data = $this->getJson('/api/v1/products/'.$product->getKey())->assertOk()->json('data');

        $this->assertSame([], $data['lots'], 'Invariant 8: a serial-tracked product has no lots');
        $this->assertSame('MK-DHP484-002391', $data['serials'][0]['serial']);
        // A warranty rather than an expiry, and the client reuses the expiry machinery for it.
        $this->assertSame('2027-02-12', $data['serials'][0]['warranty_ends_at']);
        $this->assertNull($data['serials'][0]['released_at'], 'A unit still on hand has not left');
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

    public function test_a_count_commits_every_writable_line_and_names_the_rest(): void
    {
        [, $location, $product] = $this->tenant('Birinci');
        $matched = Product::create(['name' => 'Kaşar', 'base_unit' => 'adet']);
        $unrecorded = Product::create(['name' => 'Yoğurt', 'base_unit' => 'adet']);

        foreach ([$product, $matched] as $stocked) {
            $this->postJson('/api/v1/stock/receive', [
                'product_id' => $stocked->getKey(),
                'location_id' => $location->getKey(),
                'quantity' => 4,
                'expires_at' => '2026-09-01',
            ])->assertCreated();
        }

        // One shelf, three answers. This is the case the endpoint exists to handle: a row that
        // disagreed, a row that agreed, and a row holding stock the record has never seen. Committing
        // the first while naming the third is what stops one unfinished row discarding a whole count.
        $response = $this->postJson('/api/v1/stock/count', [
            'location_id' => $location->getKey(),
            'lines' => [
                ['product_id' => $product->getKey(), 'counted_quantity' => 3],
                ['product_id' => $matched->getKey(), 'counted_quantity' => 4],
                ['product_id' => $unrecorded->getKey(), 'counted_quantity' => 2],
            ],
        ])->assertOk();

        $response
            ->assertJsonPath('data.lines.0.outcome', 'written')
            ->assertJsonPath('data.lines.0.delta', '-1.000')
            ->assertJsonPath('data.lines.1.outcome', 'matched')
            ->assertJsonPath('data.lines.2.outcome', 'needs_date')
            ->assertJsonPath('data.lines.2.delta', '2.000');

        $this->assertCount(1, $response->json('data.lines.0.movement_ids'));
        $this->assertSame([], $response->json('data.lines.2.movement_ids'));

        // Exactly one count movement in the whole request: the matched line and the deferred one both
        // wrote nothing, and an empty movement list is the only thing they have in common.
        $this->assertSame(1, StockMovement::where('reason', MovementReason::StockTake)->count());
        $this->assertSame('3.000', $product->fresh()->quantityFromLedger());
        $this->assertSame('0.000', $unrecorded->fresh()->quantityFromLedger());
    }

    public function test_a_count_resolves_its_products_in_one_query(): void
    {
        [, $location, $first] = $this->tenant('Birinci');
        $second = Product::create(['name' => 'Kaşar', 'base_unit' => 'adet']);
        $third = Product::create(['name' => 'Yoğurt', 'base_unit' => 'adet']);

        DB::enableQueryLog();

        $this->postJson('/api/v1/stock/count', [
            'location_id' => $location->getKey(),
            'lines' => [
                ['product_id' => $first->getKey(), 'counted_quantity' => 0],
                ['product_id' => $second->getKey(), 'counted_quantity' => 0],
                ['product_id' => $third->getKey(), 'counted_quantity' => 0],
            ],
        ])->assertOk();

        $lookups = collect(DB::getQueryLog())
            ->filter(static fn (array $entry): bool => str_contains($entry['query'], 'from "products"'))
            ->count();

        DB::disableQueryLog();

        // ONE, not one per line. A shelf is counted forty rows at a time, so resolving inside the loop
        // was forty round trips for a set the query builder can fetch at once. Pinned as a number
        // rather than left to review, because an N+1 reintroduced later reads exactly like the version
        // that was correct.
        $this->assertSame(1, $lookups, 'the products should be resolved in a single query');
    }

    public function test_a_count_naming_another_tenants_product_is_404_and_writes_nothing(): void
    {
        [, , $theirProduct] = $this->tenant('İkinci');
        [, $location, $product] = $this->tenant('Birinci');

        $this->postJson('/api/v1/stock/receive', [
            'product_id' => $product->getKey(),
            'location_id' => $location->getKey(),
            'quantity' => 4,
        ])->assertCreated();

        // The first line is perfectly writable. Every product is resolved before the transaction opens
        // precisely so a foreign id on the second line does not leave half a shelf counted.
        $this->postJson('/api/v1/stock/count', [
            'location_id' => $location->getKey(),
            'lines' => [
                ['product_id' => $product->getKey(), 'counted_quantity' => 1],
                ['product_id' => $theirProduct->getKey(), 'counted_quantity' => 1],
            ],
        ])->assertNotFound();

        $this->assertSame(0, StockMovement::where('reason', MovementReason::StockTake)->count());
        $this->assertSame('4.000', $product->fresh()->quantityFromLedger());
    }

    public function test_a_count_refuses_two_lines_for_one_product(): void
    {
        [, $location, $product] = $this->tenant('Birinci');

        // The second line would be measured against the balance the first one wrote and come back
        // `matched`, which reads as agreement about a shelf nobody counted twice.
        $this->postJson('/api/v1/stock/count', [
            'location_id' => $location->getKey(),
            'lines' => [
                ['product_id' => $product->getKey(), 'counted_quantity' => 1],
                ['product_id' => $product->getKey(), 'counted_quantity' => 2],
            ],
        ])->assertStatus(422)->assertJsonValidationErrors('lines.0.product_id');
    }

    public function test_a_count_accepts_zero_and_refuses_less(): void
    {
        [, $location, $product] = $this->tenant('Birinci');

        $this->postJson('/api/v1/stock/receive', [
            'product_id' => $product->getKey(),
            'location_id' => $location->getKey(),
            'quantity' => 2,
        ])->assertCreated();

        // Zero is a counted empty shelf and has to be writable; the screen never sends an UNCOUNTED
        // row at all (D58), so the two facts never arrive through the same field.
        $this->postJson('/api/v1/stock/count', [
            'location_id' => $location->getKey(),
            'lines' => [['product_id' => $product->getKey(), 'counted_quantity' => 0]],
        ])->assertOk()->assertJsonPath('data.lines.0.delta', '-2.000');

        $this->assertSame('0.000', $product->fresh()->quantityFromLedger());

        $this->postJson('/api/v1/stock/count', [
            'location_id' => $location->getKey(),
            'lines' => [['product_id' => $product->getKey(), 'counted_quantity' => -1]],
        ])->assertStatus(422)->assertJsonValidationErrors('lines.0.counted_quantity');
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
