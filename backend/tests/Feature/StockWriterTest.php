<?php

namespace Tests\Feature;

use App\Enums\MovementReason;
use App\Models\Location;
use App\Models\Product;
use App\Models\ProductStock;
use App\Models\StockLot;
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
            'base_unit' => 'C62',
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

    public function test_invariant_5_a_transfer_is_pairs_of_equal_and_opposite_movements(): void
    {
        // One lot on the shelf, so one pair. The invariant is stated PER PAIR because a move
        // crossing two lots writes two of them, and the case below asserts it there as well.
        $this->writer->receive($this->product, $this->store, 10, expiresAt: '2026-09-01');

        [$out, $in] = $this->writer->transfer($this->product, $this->store, $this->kitchen, 4);

        $this->assertCount(1, $out);
        $this->assertCount(1, $in);

        $this->assertSame(-4.0, (float) $out->first()->delta);
        $this->assertSame(4.0, (float) $in->first()->delta);
        $this->assertSame(MovementReason::TransferOut, $out->first()->reason);
        $this->assertSame(MovementReason::TransferIn, $in->first()->reason);

        // Shared reference: both halves point at the destination lot their own pair created, so
        // "which move was this part of" has a single answer.
        $this->assertSame($out->first()->reference_id, $in->first()->reference_id);
        $this->assertNotNull($out->first()->reference_id);
    }

    public function test_invariant_5_holds_for_every_pair_of_a_split_transfer(): void
    {
        $this->writer->receive($this->product, $this->store, 1, expiresAt: '2026-09-01');
        $this->writer->receive($this->product, $this->store, 5, expiresAt: '2026-12-31');

        [$out, $in] = $this->writer->transfer($this->product, $this->store, $this->kitchen, 3);

        $this->assertCount(2, $out);
        $this->assertCount(2, $in);

        foreach ($out as $index => $movement) {
            $partner = $in[$index];

            $this->assertSame(-(float) $movement->delta, (float) $partner->delta);
            // Each pair carries its OWN destination lot, so two pairs never share a reference: that
            // is what keeps "which move was this part of" answerable per row.
            $this->assertSame($movement->reference_id, $partner->reference_id);
        }

        $this->assertNotSame($out[0]->reference_id, $out[1]->reference_id);
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

    public function test_a_transfer_larger_than_its_first_lot_does_not_invent_stock(): void
    {
        // **Measured before it was fixed: six units existed and eight remained.** The availability
        // check summed ALL the source lots and the debit went against the FIRST one, and
        // `StockLot::recompute` clamps at `max($remaining, 0)`, so the overdraft did not surface as a
        // negative lot. It vanished, and the shelf it left behind still counted the untouched lot in
        // full.
        //
        // The dates are what force two lots: FEFO orders by expiry, so the one-unit lot is first.
        $this->writer->receive($this->product, $this->store, 1, expiresAt: '2026-09-01');
        $this->writer->receive($this->product, $this->store, 5, expiresAt: '2026-12-31');

        $this->writer->transfer($this->product, $this->store, $this->kitchen, 3);

        // The ledger is the arbiter: six in, nothing consumed, six on hand across both shelves.
        $this->assertSame('6.000', $this->product->quantityFromLedger());

        $byLocation = ProductStock::pluck('quantity', 'location_id');
        $this->assertSame('3.000', $byLocation[$this->store->getKey()]);
        $this->assertSame('3.000', $byLocation[$this->kitchen->getKey()]);

        // And no lot was driven past empty on the way, which is the shape the clamp was hiding.
        foreach ($this->product->lots as $lot) {
            $this->assertGreaterThanOrEqual(0, (float) $lot->remaining_quantity);
        }
    }

    public function test_a_transfer_crossing_two_lots_keeps_each_ones_own_date(): void
    {
        // The quieter half of the same defect. The destination inherited the FIRST source lot's
        // dates for the WHOLE amount, so moving three across a September lot and a December lot
        // stamped all three with September: two units aged three months early, and the expiry list
        // that reads `received_at` and `expires_at` believed it.
        $this->writer->receive($this->product, $this->store, 1, expiresAt: '2026-09-01');
        $this->writer->receive($this->product, $this->store, 5, expiresAt: '2026-12-31');

        $this->writer->transfer($this->product, $this->store, $this->kitchen, 3);

        $arrived = $this->product->lots()
            ->where('location_id', $this->kitchen->getKey())
            ->get()
            ->keyBy(static fn (StockLot $lot): string => $lot->expires_at->toDateString());

        $this->assertSame(['2026-09-01', '2026-12-31'], $arrived->keys()->sort()->values()->all());
        $this->assertSame('1.000', $arrived['2026-09-01']->remaining_quantity);
        $this->assertSame('2.000', $arrived['2026-12-31']->remaining_quantity);
    }

    public function test_a_transfer_of_more_than_the_shelf_holds_is_refused(): void
    {
        // Unchanged by the split above, and worth pinning beside it: the availability check is what
        // stops the FEFO walk from running out of lots half way.
        $this->writer->receive($this->product, $this->store, 2);

        $this->expectException(RuntimeException::class);

        $this->writer->transfer($this->product, $this->store, $this->kitchen, 3);
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
