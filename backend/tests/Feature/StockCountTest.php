<?php

namespace Tests\Feature;

use App\Enums\CountOutcome;
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
 * Counting a shelf, which is the only write path that derives its own quantity (D59).
 *
 * The cases worth pinning are the ones where the right answer is to write NOTHING, because three of
 * the four outcomes do exactly that and an empty ledger looks identical for all three.
 */
final class StockCountTest extends TestCase
{
    use RefreshDatabase;

    private Product $product;

    private Location $fridge;

    private StockWriter $writer;

    protected function setUp(): void
    {
        parent::setUp();

        /** @var User $user */
        $user = User::factory()->createOne();
        $team = Team::create(['name' => 'Birinci', 'user_id' => $user->getKey()]);
        $user->forceFill(['current_team_id' => $team->getKey()])->save();
        $user->refresh();
        $this->actingAs($user);

        $this->fridge = Location::create(['name' => 'Buzdolabı']);
        $this->product = Product::create([
            'name' => 'Süt',
            'base_unit' => 'C62',
            'tracks_expiry' => true,
            'content_amount' => 1000,
            'content_unit' => 'MLT',
            'opened_shelf_life_days' => 3,
        ]);

        $this->writer = new StockWriter(new StockLedger);
    }

    public function test_a_shortfall_is_written_as_a_stock_take_outflow(): void
    {
        $this->writer->receive($this->product, $this->fridge, 6, expiresAt: '2026-09-01');

        $result = $this->writer->count($this->product, $this->fridge, 5);

        $this->assertSame(CountOutcome::Written, $result->outcome);
        $this->assertSame(-1.0, $result->delta);
        $this->assertSame('5.000', $this->product->quantityFromLedger());
        $this->assertSame('5.000', ProductStock::first()->quantity);

        $movement = StockMovement::query()->where('reason', MovementReason::StockTake)->sole();
        $this->assertSame('-1.000', $movement->delta);
    }

    public function test_a_shortfall_spanning_two_lots_takes_the_earliest_first(): void
    {
        $this->writer->receive($this->product, $this->fridge, 2, expiresAt: '2026-12-01');
        $this->writer->receive($this->product, $this->fridge, 2, expiresAt: '2026-08-20');

        // Four on the record, three on the shelf: one is missing, and FEFO says it came out of the
        // carton that expires first. Asserting the LOT rather than only the total is the point: a
        // count that took from the wrong lot would leave the same balance and the wrong expiry.
        $result = $this->writer->count($this->product, $this->fridge, 3);

        $this->assertSame(CountOutcome::Written, $result->outcome);
        $this->assertCount(1, $result->movements);

        $earliest = StockLot::query()->where('expires_at', '2026-08-20')->sole();
        $this->assertSame('1.000', $earliest->remaining_quantity);
        $this->assertSame('2.000', StockLot::query()->where('expires_at', '2026-12-01')->sole()->remaining_quantity);
    }

    public function test_a_match_writes_nothing(): void
    {
        $this->writer->receive($this->product, $this->fridge, 4, expiresAt: '2026-09-01');

        $result = $this->writer->count($this->product, $this->fridge, 4);

        $this->assertSame(CountOutcome::Matched, $result->outcome);
        $this->assertSame(0.0, $result->delta);
        $this->assertTrue($result->movements->isEmpty());

        // The forecast tier is decided by how many movements a product has, so a zero-delta row would
        // buy this product history it did not earn. One movement, and it is the purchase.
        $this->assertSame(1, StockMovement::query()->count());
        $this->assertSame(0, StockMovement::query()->where('reason', MovementReason::StockTake)->count());
    }

    public function test_a_surplus_joins_the_earliest_sealed_lot_and_inherits_its_date(): void
    {
        $this->writer->receive($this->product, $this->fridge, 3, expiresAt: '2026-12-01');
        $this->writer->receive($this->product, $this->fridge, 3, expiresAt: '2026-08-18');

        // Seven found where six were recorded. The extra one has no date of its own, so it joins the
        // carton batch that expires FIRST: if that guess is wrong it warns early, which is the
        // direction worth being wrong in.
        $result = $this->writer->count($this->product, $this->fridge, 7);

        $this->assertSame(CountOutcome::Written, $result->outcome);
        $this->assertSame(1.0, $result->delta);

        $earliest = StockLot::query()->where('expires_at', '2026-08-18')->sole();
        $this->assertSame('4.000', $earliest->remaining_quantity);
        $this->assertSame('3.000', StockLot::query()->where('expires_at', '2026-12-01')->sole()->remaining_quantity);
        $this->assertSame('7.000', ProductStock::first()->quantity);
    }

    public function test_a_surplus_with_no_sealed_lot_is_deferred_and_writes_nothing(): void
    {
        // Nothing on the record at this location at all, so there is no neighbouring batch to take a
        // date from. Inventing one is what this refuses to do.
        $result = $this->writer->count($this->product, $this->fridge, 2);

        $this->assertSame(CountOutcome::NeedsDate, $result->outcome);
        $this->assertSame(2.0, $result->delta);
        $this->assertSame(0, StockMovement::query()->count());
        $this->assertNull(ProductStock::first());
    }

    public function test_a_surplus_beside_an_opened_lot_alone_is_deferred(): void
    {
        $this->writer->receive($this->product, $this->fridge, 1, expiresAt: '2026-09-01');
        // Half of the only carton drunk, which marks it opened (D27). An opened lot is on a clock the
        // printed date knows nothing about, so a unit found beside it cannot inherit from it: the
        // surplus is sealed stock and the neighbour's date is no longer the printed one.
        $this->writer->consume($this->product, $this->fridge, 0.5);

        $this->assertNotNull(StockLot::query()->sole()->opened_at);

        $result = $this->writer->count($this->product, $this->fridge, 1.5);

        $this->assertSame(CountOutcome::NeedsDate, $result->outcome);
        $this->assertSame(1.0, $result->delta);
        $this->assertSame(0, StockMovement::query()->where('reason', MovementReason::StockTake)->count());
        $this->assertSame('0.500', ProductStock::first()->quantity);
    }

    public function test_a_fractional_surplus_marks_the_lot_it_lands_in_as_opened(): void
    {
        $this->writer->receive($this->product, $this->fridge, 1, expiresAt: '2026-12-01');

        // "One sealed carton and 500 ml" is 1.5, and the half can only be a unit somebody opened. The
        // record did not know, so the count is what discovers it.
        $result = $this->writer->count($this->product, $this->fridge, 1.5);

        $this->assertSame(CountOutcome::Written, $result->outcome);

        $lot = StockLot::query()->sole();
        $this->assertSame('1.500', $lot->remaining_quantity);
        $this->assertNotNull($lot->opened_at, 'a fractional count means a unit is open, whatever the record said');

        // The opened clock is shorter than the printed date, so the pair's binding date moves in.
        $this->assertTrue(
            $lot->bindingDate()?->lessThan('2026-12-01') ?? false,
            'an opened lot binds on the shorter of the two clocks (D27)',
        );
    }

    public function test_a_serial_tracked_product_is_deferred_without_reading_its_lots(): void
    {
        $drill = Product::create([
            'name' => 'Matkap',
            'base_unit' => 'C62',
            'tracking_mode' => 'serial',
        ]);

        $result = $this->writer->count($drill, $this->fridge, 2);

        $this->assertSame(CountOutcome::SerialTracked, $result->outcome);
        // Zero rather than a surplus of two: a serial product's quantity is the count of its units, so
        // summing its lots would report the whole shelf as found stock.
        $this->assertSame(0.0, $result->delta);
        $this->assertSame(0, StockMovement::query()->count());
    }

    public function test_committing_the_same_count_twice_writes_once(): void
    {
        $this->writer->receive($this->product, $this->fridge, 6, expiresAt: '2026-09-01');

        $first = $this->writer->count($this->product, $this->fridge, 5);
        $second = $this->writer->count($this->product, $this->fridge, 5);

        // Idempotent by construction rather than by an idempotency key: the second submit derives its
        // delta from the balance the first one produced and finds nothing to do. This is why `count`
        // takes no key while `receive` needs one.
        $this->assertSame(CountOutcome::Written, $first->outcome);
        $this->assertSame(CountOutcome::Matched, $second->outcome);
        $this->assertSame('5.000', $this->product->quantityFromLedger());
        $this->assertSame(1, StockMovement::query()->where('reason', MovementReason::StockTake)->count());
    }

    public function test_a_counted_empty_shelf_writes_the_balance_off(): void
    {
        $this->writer->receive($this->product, $this->fridge, 3, expiresAt: '2026-09-01');

        $result = $this->writer->count($this->product, $this->fridge, 0);

        // Zero is a fact, and a different one from an uncounted row: the screen never sends an
        // untouched line (D58), so a zero arriving here was typed by somebody looking at a bare shelf.
        $this->assertSame(CountOutcome::Written, $result->outcome);
        $this->assertSame(-3.0, $result->delta);
        $this->assertSame('0.000', $this->product->quantityFromLedger());
        $this->assertNull(ProductStock::first(), 'a depleted pair is removed rather than kept at zero');
    }

    public function test_a_negative_count_is_refused(): void
    {
        $this->expectException(RuntimeException::class);

        $this->writer->count($this->product, $this->fridge, -1);
    }

    public function test_consume_still_refuses_the_stock_take_reason(): void
    {
        $this->writer->receive($this->product, $this->fridge, 3, expiresAt: '2026-09-01');

        // The guard that keeps the vocabulary meaningful. If `consume` accepted this reason a client
        // could label a plain outflow as a count, and the shrinkage figure reads that label.
        $this->expectException(RuntimeException::class);

        $this->writer->consume($this->product, $this->fridge, 1, MovementReason::StockTake);
    }
}
