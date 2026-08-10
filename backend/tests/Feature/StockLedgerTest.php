<?php

namespace Tests\Feature;

use App\Enums\ActorType;
use App\Enums\MovementReason;
use App\Enums\MovementSource;
use App\Models\Location;
use App\Models\Product;
use App\Models\StockLot;
use App\Models\StockMovement;
use App\Models\Team;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use RuntimeException;
use Tests\TestCase;

/**
 * The ledger invariants, 1 through 5 of `docs/depools-system/data-model.md`.
 *
 * Each one is written from the sentence in the doc rather than from the code, which is what caught
 * an off-by-one in the location depth guard when the same approach was used there.
 */
final class StockLedgerTest extends TestCase
{
    use RefreshDatabase;

    private Product $product;

    private Location $location;

    protected function setUp(): void
    {
        parent::setUp();

        $user = User::factory()->create();
        $team = Team::create(['name' => 'Birinci', 'user_id' => $user->getKey()]);
        $user->forceFill(['current_team_id' => $team->getKey()])->save();
        $this->actingAs($user->refresh());

        $this->location = Location::create(['name' => 'Mutfak']);
        $this->product = Product::create(['name' => 'Süt', 'base_unit' => 'adet']);
    }

    private function lot(float $initial = 10): StockLot
    {
        return StockLot::create([
            'product_id' => $this->product->getKey(),
            'location_id' => $this->location->getKey(),
            'initial_quantity' => $initial,
        ]);
    }

    private function move(StockLot $lot, float $delta, MovementReason $reason): StockMovement
    {
        return StockMovement::create([
            'product_id' => $lot->product_id,
            'location_id' => $lot->location_id,
            'stock_lot_id' => $lot->getKey(),
            'delta' => $delta,
            'reason' => $reason,
            'source' => MovementSource::Manual,
            'actor_type' => ActorType::User,
            'occurred_at' => now(),
        ]);
    }

    public function test_invariant_2_remaining_is_initial_plus_the_sum_of_deltas(): void
    {
        $lot = $this->lot(10);

        $this->move($lot, -3, MovementReason::Consumption);
        $this->move($lot, -2, MovementReason::Waste);

        $this->assertSame('5.000', $lot->refresh()->remaining_quantity);
    }

    public function test_invariant_2_remaining_never_goes_negative(): void
    {
        $lot = $this->lot(2);

        $this->move($lot, -5, MovementReason::Consumption);

        // The clamp is a containment measure, not a correction: whatever wrote an over-draw is
        // still wrong, and the ledger below still says -5. What the clamp prevents is that bug
        // spreading into every total that reads this column.
        $this->assertSame('0.000', $lot->refresh()->remaining_quantity);
        $this->assertNotNull($lot->refresh()->closed_at);
    }

    public function test_invariant_4_a_movement_cannot_be_updated(): void
    {
        $movement = $this->move($this->lot(), -1, MovementReason::Consumption);

        $this->expectException(RuntimeException::class);

        $movement->update(['delta' => -99]);
    }

    public function test_invariant_4_a_movement_cannot_be_deleted(): void
    {
        $movement = $this->move($this->lot(), -1, MovementReason::Consumption);

        $this->expectException(RuntimeException::class);

        $movement->delete();
    }

    public function test_a_mistake_is_undone_by_a_compensating_movement(): void
    {
        $lot = $this->lot(10);

        $this->move($lot, -7, MovementReason::Consumption);
        $this->move($lot, 7, MovementReason::Correction);

        // Back to ten, and the ledger still holds BOTH rows. An audit that could only see the
        // final state could not tell this tenant from one that never made the mistake.
        $this->assertSame('10.000', $lot->refresh()->remaining_quantity);
        $this->assertSame(2, $lot->movements()->count());
    }

    public function test_invariant_1_product_quantity_equals_the_sum_of_the_ledger(): void
    {
        $lot = $this->lot(10);
        $this->move($lot, 10, MovementReason::Purchase);
        $this->move($lot, -4, MovementReason::Consumption);

        $second = $this->lot(5);
        $this->move($second, 5, MovementReason::Purchase);

        // `'11.000'`, not `'11'`, and the change is the test getting stricter rather than looser.
        // It used to pass because SQLite handed back `11` while PostgreSQL sums `numeric(12,3)` into
        // `'11.000'`, so the assertion was pinning one driver's formatting instead of the invariant.
        // `quantityFromLedger()` now returns the schema's own scale on every driver, which also makes
        // it match `remaining_quantity` above: the two numbers an audit reconciles by hand are
        // formatted alike.
        $this->assertSame('11.000', $this->product->quantityFromLedger());
    }

    public function test_invariant_3_waste_is_never_folded_into_consumption(): void
    {
        $lot = $this->lot(10);
        $this->move($lot, -3, MovementReason::Consumption);
        $this->move($lot, -2, MovementReason::Waste);

        // The ratio this separation exists for. Folding waste into consumption makes both the
        // waste percentage and sell-through-before-expiry unrecoverable from the ledger.
        $waste = (float) $this->product->movements()->where('reason', MovementReason::Waste)->sum('delta');
        $outflow = (float) $this->product->movements()->where('delta', '<', 0)->sum('delta');

        $this->assertSame(0.4, round($waste / $outflow, 3));
    }

    public function test_the_idempotency_key_is_unique_per_team_and_not_globally(): void
    {
        $lot = $this->lot(10);

        StockMovement::create([
            'product_id' => $lot->product_id,
            'location_id' => $lot->location_id,
            'stock_lot_id' => $lot->getKey(),
            'delta' => -1,
            'reason' => MovementReason::Consumption,
            'source' => MovementSource::Mcp,
            'actor_type' => ActorType::McpClient,
            'idempotency_key' => 'abc-123',
            'occurred_at' => now(),
        ]);

        // A second tenant using the same client-side key is a coincidence rather than a duplicate.
        // A global unique index would let one tenant block another's write by guessing a key.
        $other = User::factory()->create();
        $otherTeam = Team::create(['name' => 'İkinci', 'user_id' => $other->getKey()]);
        $other->forceFill(['current_team_id' => $otherTeam->getKey()])->save();
        $this->actingAs($other->refresh());

        $otherLocation = Location::create(['name' => 'Depo']);
        $otherProduct = Product::create(['name' => 'Un']);
        $otherLot = StockLot::create([
            'product_id' => $otherProduct->getKey(),
            'location_id' => $otherLocation->getKey(),
            'initial_quantity' => 1,
        ]);

        $second = StockMovement::create([
            'product_id' => $otherLot->product_id,
            'location_id' => $otherLot->location_id,
            'stock_lot_id' => $otherLot->getKey(),
            'delta' => -1,
            'reason' => MovementReason::Consumption,
            'source' => MovementSource::Mcp,
            'actor_type' => ActorType::McpClient,
            'idempotency_key' => 'abc-123',
            'occurred_at' => now(),
        ]);

        $this->assertNotNull($second->getKey());
    }

    public function test_invariant_6_a_tenant_cannot_see_another_tenants_movements(): void
    {
        $lot = $this->lot(10);
        $this->move($lot, -1, MovementReason::Consumption);

        $other = User::factory()->create();
        $otherTeam = Team::create(['name' => 'İkinci', 'user_id' => $other->getKey()]);
        $other->forceFill(['current_team_id' => $otherTeam->getKey()])->save();
        $this->actingAs($other->refresh());

        $this->assertSame(0, StockMovement::count());
        $this->assertSame(0, StockLot::count());
        $this->assertSame(0, Product::count());
    }
}
