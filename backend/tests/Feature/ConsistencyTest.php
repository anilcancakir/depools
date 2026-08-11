<?php

namespace Tests\Feature;

use App\Models\GlobalProduct;
use App\Models\Location;
use App\Models\Product;
use App\Models\ProductSerial;
use App\Models\Scopes\TeamScope;
use App\Models\StockLot;
use App\Models\Team;
use App\Models\User;
use App\Services\ConsistencyFinding;
use App\Services\StockConsistency;
use App\Services\StockWriter;
use Illuminate\Database\QueryException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use RuntimeException;
use Tests\TestCase;

/**
 * The check D81 calls mandatory, and the four invariants no CHECK can reach.
 *
 * Every violation here is produced with a raw query, because that is the only way to produce one: the
 * write paths refuse them all. That is exactly what the sweep is for. D81 chose an application-
 * maintained projection over a trigger and wrote the price down: "here it is the only thing that
 * catches the failure this design permits". A test that could not manufacture the failure would be
 * testing nothing.
 */
final class ConsistencyTest extends TestCase
{
    use RefreshDatabase;

    private StockConsistency $consistency;

    private Product $product;

    private Location $shelf;

    protected function setUp(): void
    {
        parent::setUp();

        $user = User::factory()->create();
        $team = Team::create(['name' => 'Kafe', 'user_id' => $user->getKey()]);
        $user->forceFill(['current_team_id' => $team->getKey()])->save();
        $this->actingAs($user->refresh());

        $this->consistency = app(StockConsistency::class);
        $this->shelf = Location::create(['name' => 'Raf']);
        $this->product = Product::create(['name' => 'Pınar Süt']);

        app(StockWriter::class)->receive($this->product, $this->shelf, 10);
    }

    /** @return Collection<int, ConsistencyFinding> */
    private function sweep(): Collection
    {
        // Logged out, because the scheduler is. A sweep that ran inside one tenant's scope would find
        // only that tenant's drift, which is the failure mode `LedgerWithoutAuthTest` exists for.
        Auth::logout();

        return $this->consistency->sweep();
    }

    private function checks(): array
    {
        return $this->sweep()->pluck('check')->all();
    }

    public function test_a_database_built_through_the_writer_reports_nothing(): void
    {
        // The floor. Without this assertion every test below could pass on a sweep that reports
        // everything, and a check that always fires is worse than no check at all.
        $this->assertSame([], $this->checks());
    }

    public function test_a_projection_edited_behind_the_service_is_caught(): void
    {
        DB::table('product_stock')->update(['quantity' => 4]);

        $findings = $this->sweep();

        // The failure D81 accepted: something wrote the projection without going through the ledger.
        $this->assertSame(['projection_drift'], $findings->pluck('check')->all());
        $this->assertSame('10.000', $findings->first()->expected);
        $this->assertSame('4.000', $findings->first()->actual);
        $this->assertSame(1, $findings->first()->invariant);
    }

    public function test_a_movement_inserted_behind_the_service_is_caught(): void
    {
        // The literal shape of D81's first obligation being broken: a row in the ledger that
        // `StockWriter` did not write, so nothing refreshed what the ledger derives.
        DB::table('stock_movements')->insert([
            'id' => (string) Str::uuid7(),
            'team_id' => $this->product->team_id,
            'product_id' => $this->product->getKey(),
            'location_id' => $this->shelf->getKey(),
            'stock_lot_id' => StockLot::query()->withoutGlobalScope(TeamScope::class)->value('id'),
            'delta' => -3,
            'reason' => 'consumption',
            'source' => 'manual',
            'actor_type' => 'system',
            'occurred_at' => now(),
            'created_at' => now(),
        ]);

        $checks = $this->checks();

        // Both halves drift, because the lot's total and the pair's total are two derived numbers and
        // the bypass moved neither.
        $this->assertContains('projection_drift', $checks);
        $this->assertContains('lot_drift', $checks);
    }

    public function test_a_missing_projection_is_caught(): void
    {
        DB::table('product_stock')->delete();

        $findings = $this->sweep();

        // Not the same finding as drift, and the distinction is worth keeping: a stock list renders
        // this as the product having no stock anywhere, which reads as correct rather than as broken.
        $this->assertSame(['projection_missing'], $findings->pluck('check')->all());
        $this->assertSame('no product_stock row', $findings->first()->actual);
    }

    public function test_a_projection_describing_nothing_is_caught(): void
    {
        $other = Product::create(['name' => 'Hayalet']);

        DB::table('product_stock')->insert([
            'id' => (string) Str::uuid7(),
            'team_id' => $other->team_id,
            'product_id' => $other->getKey(),
            'location_id' => $this->shelf->getKey(),
            'quantity' => 7,
            'lots_count' => 1,
            'updated_at' => now(),
        ]);

        // A projection row with no movements behind it at all. The user sees seven of something the
        // shelf has never held, and no ledger comparison would find it: there is nothing to compare.
        $this->assertSame(['projection_orphaned'], $this->checks());
    }

    public function test_a_projection_left_at_zero_is_caught(): void
    {
        app(StockWriter::class)->consume($this->product, $this->shelf, 10);

        DB::table('product_stock')->insert([
            'id' => (string) Str::uuid7(),
            'team_id' => $this->product->team_id,
            'product_id' => $this->product->getKey(),
            'location_id' => $this->shelf->getKey(),
            'quantity' => 0,
            'lots_count' => 0,
            'updated_at' => now(),
        ]);

        // `rebuildProductStock` removes an emptied pair rather than keeping it at zero, so a surviving
        // zero row is drift even though its number agrees with the ledger. Comparing quantities alone
        // would have missed this one.
        $this->assertSame(['projection_orphaned'], $this->checks());
    }

    public function test_a_lot_total_edited_behind_the_service_is_caught(): void
    {
        DB::table('stock_lots')->update(['remaining_quantity' => 2]);

        $findings = $this->sweep();

        $this->assertContains('lot_drift', $findings->pluck('check')->all());
        $this->assertSame(2, $findings->firstWhere('check', 'lot_drift')->invariant);
    }

    public function test_a_negative_lot_total_cannot_be_stored_at_all(): void
    {
        $this->expectException(QueryException::class);

        // This used to assert that the SWEEP caught a negative lot. It cannot any more, because the
        // database refuses one: invariant 2's second clause is single-column and was therefore inside
        // what D84 permits the whole time. So the check moved from a nightly report to an impossibility,
        // and the sweep's `lot_negative` was deleted rather than left as a branch nothing can reach.
        DB::table('stock_lots')->update(['remaining_quantity' => -1]);
    }

    public function test_a_lot_the_ledger_drove_below_zero_is_caught_despite_the_clamp(): void
    {
        DB::table('stock_movements')->insert([
            'id' => (string) Str::uuid7(),
            'team_id' => $this->product->team_id,
            'product_id' => $this->product->getKey(),
            'location_id' => $this->shelf->getKey(),
            'stock_lot_id' => StockLot::query()->withoutGlobalScope(TeamScope::class)->value('id'),
            'delta' => -15,
            'reason' => 'consumption',
            'source' => 'manual',
            'actor_type' => 'system',
            'occurred_at' => now(),
            'created_at' => now(),
        ]);
        DB::table('stock_lots')->update(['remaining_quantity' => 0]);

        $findings = $this->sweep();

        // The clause the clamp hides, and the reason this check compares against the UNCLAMPED sum.
        // The lot sits at exactly zero and looks correct; the ledger says minus five.
        $overdrawn = $findings->firstWhere('check', 'lot_overdrawn');

        $this->assertNotNull($overdrawn);
        $this->assertSame('-5.000', $overdrawn->actual);
        $this->assertFalse($overdrawn->repairable);
    }

    public function test_a_product_holding_both_lots_and_serials_is_caught(): void
    {
        DB::table('products')->where('id', $this->product->getKey())->update(['tracking_mode' => 'serial']);

        ProductSerial::create([
            'product_id' => $this->product->getKey(),
            'location_id' => $this->shelf->getKey(),
            'serial' => 'SN-1',
            'acquired_at' => now(),
        ]);

        $findings = $this->sweep();
        $conflict = $findings->firstWhere('check', 'tracking_mode_conflict');

        // Invariant 8, and it is deliberately NOT repairable: which of the two numbers is the shelf is
        // a question about a shelf. Picking one would destroy the evidence that a writer bypassed the
        // guard, which per D81 is the actual finding.
        $this->assertNotNull($conflict);
        $this->assertSame(8, $conflict->invariant);
        $this->assertFalse($conflict->repairable);
    }

    public function test_a_serial_quantity_that_disagrees_with_the_ledger_is_caught(): void
    {
        $serialProduct = Product::create(['name' => 'Makita Matkap', 'tracking_mode' => 'serial']);

        foreach (['SN-1', 'SN-2'] as $serial) {
            ProductSerial::create([
                'product_id' => $serialProduct->getKey(),
                'location_id' => $this->shelf->getKey(),
                'serial' => $serial,
                'acquired_at' => now(),
            ]);
        }

        // Two drills on the shelf and one movement in the ledger. Invariant 9 says the two numbers are
        // the same number, so one of them is a lie and the sweep does not get to decide which.
        DB::table('stock_movements')->insert([
            'id' => (string) Str::uuid7(),
            'team_id' => $serialProduct->team_id,
            'product_id' => $serialProduct->getKey(),
            'location_id' => $this->shelf->getKey(),
            'delta' => 1,
            'reason' => 'purchase',
            'source' => 'manual',
            'actor_type' => 'system',
            'occurred_at' => now(),
            'created_at' => now(),
        ]);

        $finding = $this->sweep()->firstWhere('check', 'serial_quantity_drift');

        $this->assertNotNull($finding);
        $this->assertSame('2.000 held serials', $finding->expected);
        $this->assertSame('1.000 in the ledger', $finding->actual);
    }

    public function test_a_fractional_movement_on_a_serial_product_is_caught(): void
    {
        $serialProduct = Product::create(['name' => 'Makita Matkap', 'tracking_mode' => 'serial']);

        DB::table('stock_movements')->insert([
            'id' => (string) Str::uuid7(),
            'team_id' => $serialProduct->team_id,
            'product_id' => $serialProduct->getKey(),
            'location_id' => $this->shelf->getKey(),
            'delta' => 3,
            'reason' => 'purchase',
            'source' => 'manual',
            'actor_type' => 'system',
            'occurred_at' => now(),
            'created_at' => now(),
        ]);

        // Half a drill does not exist, and neither do three of them in one movement: each serial is one
        // physical unit, so a delta of three cannot say which three.
        $this->assertContains('serial_unit_delta', $this->checks());
    }

    public function test_a_stale_normalised_name_is_caught_on_a_tenant_product(): void
    {
        // The gap `NormalisesName` names rather than implies: a query-builder update bypasses mutators
        // AND observers, so the fold goes stale, the row still looks present, and the resolution
        // cascade quietly stops finding it. Its docblock promised this check by name.
        DB::table('products')->where('id', $this->product->getKey())->update(['name' => 'Sütaş Süt']);

        $finding = $this->sweep()->firstWhere('check', 'name_normalized_drift');

        $this->assertNotNull($finding);
        $this->assertSame('sutas sut', $finding->expected);
        $this->assertSame('pinar sut', $finding->actual);
        $this->assertNull($finding->invariant);
    }

    public function test_a_stale_normalised_name_is_caught_on_the_shared_catalog(): void
    {
        $entry = GlobalProduct::create([
            'name' => 'Pınar Süt Tam Yağlı 1 lt',
            'locale' => 'tr-TR',
            'source' => 'community',
        ]);

        DB::table('global_products')->where('id', $entry->getKey())->update(['name' => 'Içim Süt']);

        $finding = $this->sweep()->firstWhere('check', 'name_normalized_drift');

        // The shared tables carry no tenant, so a finding on one belongs to no team rather than to an
        // unknown one. Selecting `team_id` across all three tables is what broke first.
        $this->assertNotNull($finding);
        $this->assertNull($finding->teamId);
        $this->assertSame('icim sut', $finding->expected);
    }

    public function test_the_sweep_sees_every_tenant(): void
    {
        $otherUser = User::factory()->create();
        $otherTeam = Team::create(['name' => 'Dükkan', 'user_id' => $otherUser->getKey()]);
        $otherUser->forceFill(['current_team_id' => $otherTeam->getKey()])->save();
        $this->actingAs($otherUser->refresh());

        $otherProduct = Product::create(['name' => 'Ekmek']);
        $otherShelf = Location::create(['name' => 'Tezgah']);
        app(StockWriter::class)->receive($otherProduct, $otherShelf, 5);

        DB::table('product_stock')->update(['quantity' => 1]);

        $teams = $this->sweep()->pluck('teamId')->unique();

        // A sweep that only saw one tenant would be a sweep that missed the drift, and `TeamScope`
        // fails closed hard enough that this is the default rather than an edge case.
        $this->assertCount(2, $teams);
    }

    public function test_repairing_a_drifted_projection_restores_the_ledger_number(): void
    {
        DB::table('product_stock')->update(['quantity' => 999]);

        $this->consistency->repair($this->sweep()->first());

        $this->assertSame('10.000', (string) DB::table('product_stock')->value('quantity'));
        $this->assertSame([], $this->checks());
    }

    public function test_repairing_a_missing_projection_recreates_it(): void
    {
        DB::table('product_stock')->delete();

        $this->consistency->repair($this->sweep()->first());

        $this->assertSame(1, DB::table('product_stock')->count());
        $this->assertSame([], $this->checks());
    }

    public function test_repairing_an_orphaned_projection_removes_it(): void
    {
        app(StockWriter::class)->consume($this->product, $this->shelf, 10);
        DB::table('product_stock')->insert([
            'id' => (string) Str::uuid7(),
            'team_id' => $this->product->team_id,
            'product_id' => $this->product->getKey(),
            'location_id' => $this->shelf->getKey(),
            'quantity' => 0,
            'lots_count' => 0,
            'updated_at' => now(),
        ]);

        $this->consistency->repair($this->sweep()->first());

        $this->assertSame(0, DB::table('product_stock')->count());
    }

    public function test_repairing_a_stale_name_reruns_the_mutator_rather_than_a_second_fold(): void
    {
        DB::table('products')->where('id', $this->product->getKey())->update(['name' => 'Sütaş Süt']);

        $this->consistency->repair($this->sweep()->firstWhere('check', 'name_normalized_drift'));

        // Reassigning `name` is the repair, so the fold that runs is the one `NormalisesName` defines
        // and not a copy of it that could disagree.
        $this->assertSame('sutas sut', $this->product->refresh()->name_normalized);
        $this->assertSame([], $this->checks());
    }

    public function test_repairing_twice_converges_rather_than_overshooting(): void
    {
        DB::table('product_stock')->update(['quantity' => 999]);

        $finding = $this->sweep()->first();
        $this->consistency->repair($finding);
        $this->consistency->repair($finding);

        // Rebuilt from the ledger rather than adjusted by the difference, which is what makes a retried
        // job or a double-fired event safe.
        $this->assertSame('10.000', (string) DB::table('product_stock')->value('quantity'));
    }

    public function test_a_finding_with_no_authority_refuses_to_be_repaired(): void
    {
        DB::table('products')->where('id', $this->product->getKey())->update(['tracking_mode' => 'serial']);
        ProductSerial::create([
            'product_id' => $this->product->getKey(),
            'location_id' => $this->shelf->getKey(),
            'serial' => 'SN-1',
            'acquired_at' => now(),
        ]);

        $conflict = $this->sweep()->firstWhere('check', 'tracking_mode_conflict');

        $this->expectException(RuntimeException::class);

        // Refused loudly rather than skipped silently. A repair loop that quietly passed over these
        // would report "all repaired" while leaving the findings that actually need a person.
        $this->consistency->repair($conflict);
    }

    public function test_the_command_succeeds_on_a_clean_database(): void
    {
        Auth::logout();

        $this->artisan('depools:check-consistency')
            ->expectsOutputToContain('No drift')
            ->assertExitCode(0);
    }

    public function test_the_command_fails_without_fixing_by_default(): void
    {
        DB::table('product_stock')->update(['quantity' => 4]);

        Auth::logout();

        $this->artisan('depools:check-consistency')->assertExitCode(1);

        // Untouched, and that is the decision rather than an oversight: drift is the evidence that a
        // writer bypassed the service, so the scheduled run reports and a person reads why.
        $this->assertSame('4.000', (string) DB::table('product_stock')->value('quantity'));
    }

    public function test_the_command_repairs_and_then_succeeds_with_fix(): void
    {
        DB::table('product_stock')->update(['quantity' => 4]);
        DB::table('stock_lots')->update(['remaining_quantity' => 2]);

        Auth::logout();

        $this->artisan('depools:check-consistency --fix')->assertExitCode(0);

        $this->assertSame('10.000', (string) DB::table('product_stock')->value('quantity'));
        $this->assertSame('10.000', (string) DB::table('stock_lots')->value('remaining_quantity'));
    }

    public function test_the_command_still_fails_when_something_needs_a_person(): void
    {
        DB::table('product_stock')->update(['quantity' => 4]);
        DB::table('products')->where('id', $this->product->getKey())->update(['tracking_mode' => 'serial']);
        ProductSerial::create([
            'product_id' => $this->product->getKey(),
            'location_id' => $this->shelf->getKey(),
            'serial' => 'SN-1',
            'acquired_at' => now(),
        ]);

        Auth::logout();

        // The repairable half is fixed and the exit code still says something is open, because a green
        // exit on a half-handled sweep is how the remaining half gets forgotten.
        $this->artisan('depools:check-consistency --fix')->assertExitCode(1);

        $this->assertSame('10.000', (string) DB::table('product_stock')->value('quantity'));
    }
}
