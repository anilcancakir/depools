<?php

namespace Tests\Feature;

use App\Enums\MovementReason;
use App\Models\Location;
use App\Models\Product;
use App\Models\ProductStock;
use App\Models\StockMovement;
use App\Models\Team;
use App\Models\User;
use App\Services\StockLedger;
use App\Services\StockWriter;
use Illuminate\Foundation\Testing\RefreshDatabase;
use RuntimeException;
use Tests\TestCase;

/**
 * The write path, including invariant 5 (a transfer is exactly two equal and opposite movements
 * with a shared reference).
 */
final class StockWriterTest extends TestCase
{
    use RefreshDatabase;

    private Product $product;

    private Location $kitchen;

    private Location $store;

    private StockWriter $writer;

    protected function setUp(): void
    {
        parent::setUp();

        $user = User::factory()->create();
        $team = Team::create(['name' => 'Birinci', 'user_id' => $user->getKey()]);
        $user->forceFill(['current_team_id' => $team->getKey()])->save();
        $this->actingAs($user->refresh());

        $this->kitchen = Location::create(['name' => 'Mutfak']);
        $this->store = Location::create(['name' => 'Depo']);
        $this->product = Product::create([
            'name' => 'Süt',
            'base_unit' => 'adet',
            'tracks_expiry' => true,
            'opened_shelf_life_days' => 3,
        ]);

        $this->writer = new StockWriter(new StockLedger);
    }

    public function test_receiving_creates_a_lot_and_a_ledger_row_that_agree(): void
    {
        $this->writer->receive($this->product, $this->kitchen, 6, expiresAt: '2026-09-01');

        $this->assertSame('6.000', $this->product->quantityFromLedger());
        $this->assertSame('6.000', $this->product->lots()->first()->remaining_quantity);
        $this->assertSame('6.000', ProductStock::first()->quantity);
    }

    public function test_consumption_takes_from_the_fefo_lot_first(): void
    {
        $this->writer->receive($this->product, $this->kitchen, 5, expiresAt: '2026-12-01');
        $this->writer->receive($this->product, $this->kitchen, 5, expiresAt: '2026-08-20');

        $written = $this->writer->consume($this->product, $this->kitchen, 3);

        $soonest = $this->product->lots()->orderBy('expires_at')->first();

        $this->assertCount(1, $written);
        $this->assertSame($soonest->getKey(), $written->first()->stock_lot_id);
        $this->assertSame('2.000', $soonest->refresh()->remaining_quantity);
    }

    public function test_a_consumption_spanning_two_lots_writes_one_row_per_lot(): void
    {
        $this->writer->receive($this->product, $this->kitchen, 2, expiresAt: '2026-08-20');
        $this->writer->receive($this->product, $this->kitchen, 5, expiresAt: '2026-12-01');

        $written = $this->writer->consume($this->product, $this->kitchen, 4);

        // Two facts, not one. The ledger has to say which carton each unit came from or expiry
        // tracking stops working the moment a second lot exists.
        $this->assertCount(2, $written);
        $this->assertSame(-4.0, (float) $written->sum(static fn ($m) => (float) $m->delta));
    }

    public function test_taking_more_than_exists_is_refused_rather_than_clamped(): void
    {
        $this->writer->receive($this->product, $this->kitchen, 2);

        $this->expectException(RuntimeException::class);

        // Clamping would turn a miscount, or stock that arrived unrecorded, into a silently
        // zeroed shelf the user discovers much later.
        $this->writer->consume($this->product, $this->kitchen, 5);
    }

    public function test_a_partial_consumption_opens_a_sealed_lot_without_being_told(): void
    {
        $this->writer->receive($this->product, $this->kitchen, 2, expiresAt: '2026-12-31');

        $this->writer->consume($this->product, $this->kitchen, 0.5);

        // D27's sibling reasoning: half a carton is not a carton, so the opening is a consequence
        // of what the user recorded rather than a separate declaration they have to remember.
        $lot = $this->product->lots()->first();
        $this->assertNotNull($lot->opened_at);
        $this->assertSame(
            now()->addDays(3)->toDateString(),
            $lot->bindingDate()->toDateString(),
        );
    }

    public function test_a_whole_unit_consumption_leaves_the_lot_sealed(): void
    {
        $this->writer->receive($this->product, $this->kitchen, 3, expiresAt: '2026-12-31');

        $this->writer->consume($this->product, $this->kitchen, 1);

        $this->assertNull($this->product->lots()->first()->opened_at);
    }

    public function test_invariant_5_a_transfer_is_two_equal_and_opposite_movements(): void
    {
        $this->writer->receive($this->product, $this->store, 10, expiresAt: '2026-09-01');

        [$out, $in] = $this->writer->transfer($this->product, $this->store, $this->kitchen, 4);

        $this->assertSame(-4.0, (float) $out->delta);
        $this->assertSame(4.0, (float) $in->delta);
        $this->assertSame(MovementReason::TransferOut, $out->reason);
        $this->assertSame(MovementReason::TransferIn, $in->reason);

        // Shared reference: both halves point at the destination lot, which a transfer creates
        // exactly one of, so "which move was this part of" has a single answer.
        $this->assertSame($out->reference_id, $in->reference_id);
        $this->assertNotNull($out->reference_id);
    }

    public function test_a_transfer_moves_the_total_without_changing_it(): void
    {
        $this->writer->receive($this->product, $this->store, 10, expiresAt: '2026-09-01');
        $this->writer->transfer($this->product, $this->store, $this->kitchen, 4);

        $this->assertSame('10.000', $this->product->quantityFromLedger());

        $byLocation = ProductStock::pluck('quantity', 'location_id');
        $this->assertSame('6.000', $byLocation[$this->store->getKey()]);
        $this->assertSame('4.000', $byLocation[$this->kitchen->getKey()]);
    }

    public function test_a_transfer_carries_the_expiry_date_to_the_destination(): void
    {
        $this->writer->receive($this->product, $this->store, 10, expiresAt: '2026-09-01');
        $this->writer->transfer($this->product, $this->store, $this->kitchen, 4);

        // A carton does not become fresher by being carried to another shelf. Dropping the date
        // here is how a transfer would quietly remove a product from the expiry list.
        $arrived = $this->product->lots()->where('location_id', $this->kitchen->getKey())->first();
        $this->assertSame('2026-09-01', $arrived->expires_at->toDateString());
    }

    public function test_a_transfer_to_the_same_location_is_refused(): void
    {
        $this->writer->receive($this->product, $this->store, 5);

        $this->expectException(RuntimeException::class);

        $this->writer->transfer($this->product, $this->store, $this->store, 1);
    }

    public function test_waste_is_recorded_as_waste_and_not_as_consumption(): void
    {
        $this->writer->receive($this->product, $this->kitchen, 5);
        $this->writer->consume($this->product, $this->kitchen, 2, MovementReason::Waste);

        $this->assertSame(
            -2.0,
            (float) StockMovement::where('reason', MovementReason::Waste)->sum('delta'),
        );
        $this->assertSame(
            0,
            StockMovement::where('reason', MovementReason::Consumption)->count(),
        );
    }
}
