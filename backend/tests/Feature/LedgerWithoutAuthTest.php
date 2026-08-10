<?php

namespace Tests\Feature;

use App\Models\Location;
use App\Models\Product;
use App\Models\ProductSerial;
use App\Models\Scopes\TeamScope;
use App\Models\StockLot;
use App\Models\Team;
use App\Models\User;
use App\Services\StockLedger;
use App\Services\StockWriter;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use RuntimeException;
use Tests\TestCase;

/**
 * The derivation paths work with no authenticated user, which is the test `BelongsToTeam` demands.
 *
 * Its docblock says a genuine cross-tenant read is stated explicitly by the caller "and a test covers
 * it". This is that test, and it exists because the behaviour before it was measured rather than
 * assumed: `rebuildProductStock` with no user found no lots, computed zero, took the delete branch,
 * deleted nothing (that query was scoped too) and returned as though it had rebuilt the pair. A
 * repair that silently does nothing is worse than one that throws, because the sweep would have
 * reported drift, "fixed" it, and reported the same drift the next night forever.
 *
 * Every test here logs out first. That is not a contrived setup: it is the console, the queue worker
 * and the scheduler, which is where all of this runs.
 */
final class LedgerWithoutAuthTest extends TestCase
{
    use RefreshDatabase;

    private Product $product;

    private Location $shelf;

    private Location $kitchen;

    protected function setUp(): void
    {
        parent::setUp();

        $user = User::factory()->create();
        $team = Team::create(['name' => 'Kafe', 'user_id' => $user->getKey()]);
        $user->forceFill(['current_team_id' => $team->getKey()])->save();
        $this->actingAs($user->refresh());

        $this->shelf = Location::create(['name' => 'Raf']);
        $this->kitchen = Location::create(['name' => 'Mutfak']);
        $this->product = Product::create(['name' => 'Pınar Süt']);

        app(StockWriter::class)->receive($this->product, $this->shelf, 10);
    }

    public function test_the_scope_really_does_hide_everything_from_the_console(): void
    {
        Auth::logout();

        // The premise of every other test in this file, asserted rather than assumed. If this ever
        // returns a row, `TeamScope` stopped failing closed and the tenancy guarantee went with it.
        $this->assertSame(0, Product::query()->count());
        $this->assertSame(0, StockLot::query()->count());
        $this->assertSame(1, DB::table('products')->count());
    }

    public function test_a_rebuild_with_no_user_writes_the_real_quantity(): void
    {
        DB::table('product_stock')->update(['quantity' => 999]);

        Auth::logout();

        app(StockLedger::class)->rebuildProductStock($this->product, $this->shelf->getKey());

        // The measurement that produced this whole change: before it, this assertion read 999.
        $this->assertSame('10.000', (string) DB::table('product_stock')->value('quantity'));
    }

    public function test_a_rebuild_with_no_user_does_not_insert_a_second_projection(): void
    {
        Auth::logout();

        app(StockLedger::class)->rebuildProductStock($this->product, $this->shelf->getKey());

        // The second failure the scoped `updateOrCreate` would have caused: its lookup half matched
        // nothing, so it would have INSERTED and collided with the unique index on
        // `(team_id, product_id, location_id)`. One row, updated in place.
        $this->assertSame(1, DB::table('product_stock')->count());
    }

    public function test_a_rebuild_with_no_user_still_removes_an_emptied_pair(): void
    {
        app(StockWriter::class)->consume($this->product, $this->shelf, 10);

        DB::table('product_stock')->insert([
            'id' => (string) Str::uuid7(),
            'team_id' => $this->product->team_id,
            'product_id' => $this->product->getKey(),
            'location_id' => $this->shelf->getKey(),
            'quantity' => 4,
            'lots_count' => 1,
            'updated_at' => now(),
        ]);

        Auth::logout();

        app(StockLedger::class)->rebuildProductStock($this->product, $this->shelf->getKey());

        // The delete branch has to reach the row too. A stock list showing 4 of something the shelf
        // does not have is the visible half of this bug.
        $this->assertSame(0, DB::table('product_stock')->count());
    }

    public function test_fefo_with_no_user_still_finds_the_lots(): void
    {
        Auth::logout();

        $lots = app(StockLedger::class)->fefoLots($this->product, $this->shelf->getKey());

        // Without this, a queued consumption would refuse itself with "not enough stock" against a
        // full shelf, which reads as a data problem and is a scope problem.
        $this->assertCount(1, $lots);
    }

    public function test_a_lot_recalculated_with_no_user_keeps_its_quantity(): void
    {
        $lot = StockLot::query()->firstOrFail();

        Auth::logout();

        $lot->recalculateFromLedger();

        // The destructive shape: summing an empty movement set gives `initial_quantity + 0`, which is
        // zero for every lot this application creates (`receive` zeroes it and lets the ledger fill
        // it), so the lot would be clamped to zero AND closed.
        $this->assertSame('10.000', $lot->refresh()->remaining_quantity);
        $this->assertNull($lot->closed_at);
    }

    public function test_a_movement_written_with_no_user_still_updates_its_lot(): void
    {
        Auth::logout();

        // This used to fail on a not-null violation naming `stock_lots.team_id`, because the lot's
        // tenant came from `TeamScope::currentTeamId()`. It comes from the product now, which is what
        // invariant 3 requires anyway and what makes a queued receipt parse or an import possible.
        app(StockWriter::class)->receive($this->product, $this->kitchen, 6);

        $lot = StockLot::query()
            ->withoutGlobalScope(TeamScope::class)
            ->where('location_id', $this->kitchen->getKey())
            ->firstOrFail();

        // The `created` hook resolves the lot scope-free. Otherwise the relation is null, the hook
        // does nothing, and the lot sits at zero while the ledger says six.
        $this->assertSame('6.000', $lot->remaining_quantity);
    }

    public function test_the_ledger_sum_with_no_user_is_not_zero(): void
    {
        Auth::logout();

        // `quantityFromLedger` is what the sweep compares the projection AGAINST. Scoped, it returns
        // `'0.000'` for every product, so the sweep would report the entire database as drifted and
        // its output would be indistinguishable from a real catastrophe.
        $this->assertSame('10.000', $this->product->quantityFromLedger());
    }

    public function test_the_tracking_mode_guard_still_refuses_with_no_user(): void
    {
        app(StockWriter::class)->consume($this->product, $this->shelf, 10);
        ProductSerial::create([
            'product_id' => $this->product->getKey(),
            'location_id' => $this->shelf->getKey(),
            'serial' => 'SN-1',
            'acquired_at' => now(),
        ]);
        $this->product->update(['tracking_mode' => 'serial']);

        Auth::logout();

        $this->expectException(RuntimeException::class);

        // A guard that only works for logged-in users is not a guard. Scoped, the serial lookup would
        // return nothing here and the forbidden transition would be permitted from a console.
        $this->product->update(['tracking_mode' => 'lot']);
    }
}
