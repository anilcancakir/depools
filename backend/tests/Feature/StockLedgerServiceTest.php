<?php

declare(strict_types=1);

namespace Tests\Feature;

use App\Enums\ActorType;
use App\Enums\MovementReason;
use App\Enums\MovementSource;
use App\Models\Location;
use App\Models\Product;
use App\Models\ProductStock;
use App\Models\StockLot;
use App\Models\StockMovement;
use App\Models\Team;
use App\Models\User;
use App\Services\StockLedger;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * FEFO selection and the materialised totals.
 *
 * The FEFO cases are written from D27's sentence rather than from the code, because the rule that
 * matters is the counter-intuitive half: an OPEN lot outranks a merely-earlier printed date. A test
 * that only checked "earliest date first" would pass against a pure sort and miss the whole point.
 */
final class StockLedgerServiceTest extends TestCase
{
    use RefreshDatabase;

    private Product $product;

    private Location $location;

    private StockLedger $ledger;

    protected function setUp(): void
    {
        parent::setUp();

        $user = User::factory()->create();
        $team = Team::create(['name' => 'Birinci', 'user_id' => $user->getKey()]);
        $user->forceFill(['current_team_id' => $team->getKey()])->save();
        $this->actingAs($user->refresh());

        $this->location = Location::create(['name' => 'Mutfak']);
        $this->product = Product::create([
            'name' => 'Süt',
            'base_unit' => 'adet',
            'tracks_expiry' => true,
            // Three days once opened, which is what makes an open lot outrank a sealed one.
            'opened_shelf_life_days' => 3,
        ]);
        $this->ledger = new StockLedger;
    }

    private function lot(?string $expires, float $qty = 5, ?string $opened = null): StockLot
    {
        return StockLot::create([
            'product_id' => $this->product->getKey(),
            'location_id' => $this->location->getKey(),
            'initial_quantity' => $qty,
            'expires_at' => $expires,
            'opened_at' => $opened,
            'received_at' => now(),
        ]);
    }

    public function test_fefo_orders_sealed_lots_by_printed_date(): void
    {
        $later = $this->lot('2026-09-01');
        $sooner = $this->lot('2026-08-20');

        $order = $this->ledger->fefoLots($this->product, $this->location->getKey());

        $this->assertSame($sooner->getKey(), $order->first()->getKey());
        $this->assertSame($later->getKey(), $order->last()->getKey());
    }

    public function test_an_open_lot_outranks_a_sealed_one_with_an_earlier_printed_date(): void
    {
        // The sealed carton is dated sooner. Pure FEFO would send the user to it.
        $sealedSooner = $this->lot('2026-08-10');
        $openLater = $this->lot('2026-12-31', 5, now()->toDateTimeString());

        $order = $this->ledger->fefoLots($this->product, $this->location->getKey());

        // D27: you finish the carton that is already open. Its printed date knows nothing about
        // the three-day clock that started when it was opened.
        $this->assertSame($openLater->getKey(), $order->first()->getKey());
        $this->assertSame($sealedSooner->getKey(), $order->last()->getKey());
    }

    public function test_an_undated_lot_sorts_last_rather_than_first(): void
    {
        $undated = $this->lot(null);
        $dated = $this->lot('2026-08-20');

        $order = $this->ledger->fefoLots($this->product, $this->location->getKey());

        // Sorting nulls to the front would send every consumption to the non-perishables and leave
        // the dated stock to expire, which is the exact opposite of what the feature is for.
        $this->assertSame($dated->getKey(), $order->first()->getKey());
        $this->assertSame($undated->getKey(), $order->last()->getKey());
    }

    public function test_a_closed_or_empty_lot_is_not_offered(): void
    {
        $empty = $this->lot('2026-08-01', 1);
        $this->lot('2026-12-01', 5);

        StockMovement::create([
            'product_id' => $this->product->getKey(),
            'location_id' => $this->location->getKey(),
            'stock_lot_id' => $empty->getKey(),
            'delta' => -1,
            'reason' => MovementReason::Consumption,
            'source' => MovementSource::Manual,
            'actor_type' => ActorType::User,
            'occurred_at' => now(),
        ]);

        $order = $this->ledger->fefoLots($this->product, $this->location->getKey());

        // Even though it holds the earliest date of the two.
        $this->assertCount(1, $order);
        $this->assertNotSame($empty->getKey(), $order->first()->getKey());
    }

    public function test_the_binding_date_is_the_earlier_of_printed_and_opened_plus_shelf_life(): void
    {
        $lot = $this->lot('2026-12-31', 5, now()->toDateTimeString());

        // Three days from opening beats a printed date months away.
        $this->assertSame(
            now()->addDays(3)->toDateString(),
            $lot->bindingDate()->toDateString(),
        );
    }

    public function test_product_stock_is_rebuilt_from_the_lots(): void
    {
        $this->lot('2026-08-20', 5);
        $this->lot('2026-09-01', 3);

        $stock = $this->ledger->rebuildProductStock($this->product, $this->location->getKey());

        $this->assertSame('8.000', $stock->quantity);
        $this->assertSame(2, $stock->lots_count);
        $this->assertSame('2026-08-20', $stock->earliest_expires_at->toDateString());
    }

    public function test_the_pair_is_removed_rather_than_kept_at_zero(): void
    {
        $lot = $this->lot('2026-08-20', 2);
        $this->ledger->rebuildProductStock($this->product, $this->location->getKey());

        StockMovement::create([
            'product_id' => $this->product->getKey(),
            'location_id' => $this->location->getKey(),
            'stock_lot_id' => $lot->getKey(),
            'delta' => -2,
            'reason' => MovementReason::Consumption,
            'source' => MovementSource::Manual,
            'actor_type' => ActorType::User,
            'occurred_at' => now(),
        ]);

        $this->assertNull($this->ledger->rebuildProductStock($this->product, $this->location->getKey()));

        // A stock list showing every product a tenant has ever held at every location they have
        // ever used is not a stock list.
        $this->assertSame(0, ProductStock::count());
    }

    public function test_rebuilding_twice_converges_instead_of_doubling(): void
    {
        $this->lot('2026-08-20', 4);

        $this->ledger->rebuildProductStock($this->product, $this->location->getKey());
        $second = $this->ledger->rebuildProductStock($this->product, $this->location->getKey());

        // Rebuilt from scratch rather than adjusted, so a retried job or a double-fired event
        // lands on the same number instead of drifting.
        $this->assertSame('4.000', $second->quantity);
        $this->assertSame(1, ProductStock::count());
    }
}
