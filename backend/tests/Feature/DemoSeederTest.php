<?php

namespace Tests\Feature;

use App\Enums\MovementReason;
use App\Models\Product;
use App\Models\StockLot;
use App\Models\StockMovement;
use App\Services\StockConsistency;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Illuminate\Support\Collection;
use Tests\TestCase;

/**
 * The fixture has two jobs and this pins both.
 *
 * The first is that it went through the sanctioned path. Seeding and then running the consistency
 * sweep is the strongest available check: the sweep compares the projection against the ledger and
 * each lot against its own movements, so a seeder that inserted a convenient row anywhere would show
 * up as drift. An empty sweep after seeding means the fixture and the invariants agree.
 *
 * The second is coverage. A screen is judged against data, and a status with no row is a badge nobody
 * has ever seen render. So each state the design defines is asserted to exist by the FACTS that
 * produce it rather than by a status API, because no such service exists yet and a test that invents
 * one would pin this fixture to a shape the real code has not chosen.
 */
final class DemoSeederTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();

        // Authenticates the demo user, so every assertion below reads through the tenant scope
        // exactly as a request would.
        $this->seed();
    }

    public function test_the_seeded_inventory_agrees_with_the_ledger(): void
    {
        $findings = app(StockConsistency::class)->sweep();

        $this->assertTrue(
            $findings->isEmpty(),
            'The demo fixture drifted from the ledger: '
            .$findings->map(static fn ($finding): string => $finding->describe())->implode('; '),
        );
    }

    public function test_it_covers_every_stock_state_a_screen_has_to_render(): void
    {
        $this->assertNotNull($this->productNamed('Whole Milk 1 L'), 'in-stock needs a row');

        $tablets = $this->productNamed('Dishwasher Tablets');
        $this->assertSame(
            '6.000',
            $tablets->quantityFromLedger(),
            'low-stock needs a product below its reorder point and above zero',
        );
        $this->assertTrue((float) $tablets->quantityFromLedger() < (float) $tablets->reorder_point);

        $this->assertSame(
            '0.000',
            $this->productNamed('Ground Coffee 250 g')->quantityFromLedger(),
            'out-of-stock has to be reached through the ledger, not by an absent row',
        );

        $this->assertTrue(
            $this->lotsOf('Iceberg Lettuce')->contains(
                static fn (StockLot $lot): bool => $lot->expires_at !== null
                    && Carbon::parse($lot->expires_at)->isBetween(Carbon::today(), Carbon::today()->addDays(7)),
            ),
            'expiring needs a lot inside the warning window',
        );

        $this->assertTrue(
            $this->lotsOf('Free Range Eggs')->contains(
                static fn (StockLot $lot): bool => $lot->expires_at !== null
                    && Carbon::parse($lot->expires_at)->isBefore(Carbon::today()),
            ),
            'expired needs a lot already past its date',
        );

        $this->assertTrue(
            // The enum rather than its backing string: `reason` is cast to it, so a renamed case
            // breaks this line instead of silently matching nothing.
            StockMovement::query()->where('reason', MovementReason::Waste)->exists(),
            'wasted needs a movement whose reason names it',
        );
    }

    public function test_expiry_belongs_to_a_lot_rather_than_to_the_product(): void
    {
        $dates = $this->lotsOf('Iceberg Lettuce')
            ->map(static fn (StockLot $lot): ?string => $lot->expires_at?->toDateString())
            ->filter()
            ->unique();

        $this->assertGreaterThan(
            1,
            $dates->count(),
            'One product needs two lots with different dates, or FEFO has nothing to choose between',
        );
    }

    public function test_a_serial_tracked_product_carries_no_lot(): void
    {
        $machine = $this->productNamed('Espresso Machine');

        $this->assertSame('serial', $machine->tracking_mode);
        $this->assertSame(0, $machine->lots()->count(), 'Invariant 8: lots XOR serials');
    }

    public function test_a_transfer_leaves_the_total_unchanged_across_two_locations(): void
    {
        $oil = $this->productNamed('Sunflower Oil 1 L');

        $this->assertSame('6.000', $oil->quantityFromLedger());
        $this->assertSame(
            2,
            $oil->stock()->count(),
            'A transfer produces a per-location row on each side of the move',
        );
    }

    public function test_it_refuses_to_seed_twice(): void
    {
        $before = Product::query()->count();

        $this->seed();

        $this->assertSame($before, Product::query()->count());
    }

    private function productNamed(string $name): Product
    {
        $product = Product::query()->where('name', $name)->first();

        $this->assertNotNull($product, 'The fixture no longer contains '.$name);

        return $product;
    }

    /**
     * @return Collection<int, StockLot>
     */
    private function lotsOf(string $name): Collection
    {
        return $this->productNamed($name)->lots()->get();
    }
}
