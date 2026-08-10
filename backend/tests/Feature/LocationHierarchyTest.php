<?php

namespace Tests\Feature;

use App\Models\Location;
use App\Models\Scopes\TeamScope;
use App\Models\Team;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use RuntimeException;
use Tests\TestCase;

/**
 * `path` and `depth` stay true, which is the only thing that makes storing them worth anything.
 *
 * Invariant 7 lives here rather than in a CHECK, because "no location is its own ancestor" compares
 * rows and D84 rules out the trigger that could. `data-model.md` used to claim the depth cap was in
 * the database; it is not, and this file is what the claim should have pointed at.
 *
 * Four failures were measured before these tests existed, all four silent, and three of them writing
 * WRONG data rather than doing nothing. That is worse than the drift D81 accepted responsibility for,
 * because a screen reading `path` cannot tell a stale breadcrumb from a real one.
 */
final class LocationHierarchyTest extends TestCase
{
    use RefreshDatabase;

    private Location $kitchen;

    private Location $fridge;

    private Location $shelf;

    protected function setUp(): void
    {
        parent::setUp();

        $user = User::factory()->create();
        $team = Team::create(['name' => 'Kafe', 'user_id' => $user->getKey()]);
        $user->forceFill(['current_team_id' => $team->getKey()])->save();
        $this->actingAs($user->refresh());

        $this->kitchen = Location::create(['name' => 'Mutfak']);
        $this->fridge = Location::create(['name' => 'Buzdolabı', 'parent_location_id' => $this->kitchen->getKey()]);
        $this->shelf = Location::create(['name' => 'Üst Raf', 'parent_location_id' => $this->fridge->getKey()]);
    }

    private function storedPath(Location $location): string
    {
        return DB::table('locations')->where('id', $location->getKey())->value('path');
    }

    private function storedDepth(Location $location): int
    {
        return (int) DB::table('locations')->where('id', $location->getKey())->value('depth');
    }

    public function test_the_tree_is_built_with_the_paths_it_should_have(): void
    {
        $this->assertSame('/Mutfak/', $this->storedPath($this->kitchen));
        $this->assertSame('/Mutfak/Buzdolabı/', $this->storedPath($this->fridge));
        $this->assertSame('/Mutfak/Buzdolabı/Üst Raf/', $this->storedPath($this->shelf));
        $this->assertSame(2, $this->storedDepth($this->shelf));
    }

    public function test_renaming_a_parent_repaths_its_whole_subtree(): void
    {
        $this->kitchen->update(['name' => 'Mutfak 2']);

        // `inventory-core.md` makes renaming a documented flow: "First capture creates a default
        // location rather than blocking. The user renames it later." Before this, only the renamed row
        // was re-pathed, so every shelf inside a renamed room showed the OLD room name in its
        // breadcrumb forever, because `getFullPathAttribute` reads `path` and nothing rewrote it.
        $this->assertSame('/Mutfak 2/', $this->storedPath($this->kitchen));
        $this->assertSame('/Mutfak 2/Buzdolabı/', $this->storedPath($this->fridge));
        $this->assertSame('/Mutfak 2/Buzdolabı/Üst Raf/', $this->storedPath($this->shelf));
    }

    public function test_moving_a_subtree_repaths_and_redepths_every_descendant(): void
    {
        $pantry = Location::create(['name' => 'Kiler']);

        $this->fridge->update(['parent_location_id' => $pantry->getKey()]);

        // The grandchild moved two levels without being touched, and its depth has to move with it or
        // the depth cap stops meaning anything: a subtree grafted deep would exceed 6 silently.
        $this->assertSame('/Kiler/Buzdolabı/', $this->storedPath($this->fridge));
        $this->assertSame('/Kiler/Buzdolabı/Üst Raf/', $this->storedPath($this->shelf));
        $this->assertSame(1, $this->storedDepth($this->fridge));
        $this->assertSame(2, $this->storedDepth($this->shelf));
    }

    public function test_a_rename_that_changes_nothing_does_not_rewrite_the_subtree(): void
    {
        $before = $this->storedPath($this->shelf);

        $this->kitchen->update(['name' => 'Mutfak']);

        // The cascade is triggered by `path` actually changing rather than by a save happening, so a
        // no-op update on a seven-tier tree does not rewrite every row under it.
        $this->assertSame($before, $this->storedPath($this->shelf));
    }

    public function test_a_child_saved_with_no_authenticated_user_keeps_its_place(): void
    {
        Auth::logout();

        $shelf = Location::query()->withoutGlobalScope(TeamScope::class)->findOrFail($this->shelf->getKey());
        $shelf->name = 'Üst Raf 2';
        $shelf->save();

        // Measured before the fix: `depth` went 2 to 0 and `path` became `/Üst Raf 2/` while
        // `parent_location_id` stayed set, so the row claimed to be a root AND to have a parent. The
        // cause is the same one D111 records for the ledger: the parent lookup was team-scoped, so
        // outside a request it resolved to null and the code took its "this is a root" branch.
        $this->assertSame('/Mutfak/Buzdolabı/Üst Raf 2/', $this->storedPath($shelf));
        $this->assertSame(2, $this->storedDepth($shelf));
    }

    public function test_the_cycle_guard_fires_with_no_authenticated_user(): void
    {
        Auth::logout();

        $kitchen = Location::query()->withoutGlobalScope(TeamScope::class)->findOrFail($this->kitchen->getKey());
        $kitchen->parent_location_id = $this->shelf->getKey();

        $this->expectException(RuntimeException::class);

        // Measured before the fix: this was ACCEPTED. `ancestorKeyPath` walked the chain with a scoped
        // `find`, so outside a request the walk stopped at the first level and found no cycle. A root
        // placed inside its own grandchild is exactly the MVP failure the whole path/depth design
        // exists to prevent: "one location made its own ancestor hung the query".
        $kitchen->save();
    }

    public function test_a_save_that_keeps_a_vanished_parent_is_refused(): void
    {
        $this->fridge->delete();

        $shelf = Location::query()->findOrFail($this->shelf->getKey());
        $shelf->name = 'Üst Raf 2';

        $this->expectException(RuntimeException::class);

        // Refused rather than silently rooted, and the refusal is the point. What the policy for a
        // deleted parent SHOULD be is undecided: no `destroy` endpoint exists yet and no feature doc
        // says whether deleting a room cascades to its shelves, reparents them, or is refused. So the
        // model fails loudly and the decision gets made when someone builds delete, instead of being
        // made accidentally by a branch that rooted the child and kept its `parent_location_id`.
        $shelf->save();
    }

    public function test_moving_out_from_under_a_vanished_parent_still_works(): void
    {
        $this->fridge->delete();

        $shelf = Location::query()->findOrFail($this->shelf->getKey());
        $shelf->parent_location_id = $this->kitchen->getKey();
        $shelf->save();

        // The refusal above must not trap the row. A save that RESOLVES the dangling parent is the
        // repair, and it has to be reachable or a deleted room would make its shelves unsaveable.
        $this->assertSame('/Mutfak/Üst Raf/', $this->storedPath($shelf));
        $this->assertSame(1, $this->storedDepth($shelf));
    }

    public function test_the_depth_cap_still_rejects_a_seventh_level(): void
    {
        $node = $this->shelf;

        foreach (['Kutu', 'Çekmece', 'Bölme', 'Göz'] as $name) {
            $node = Location::create(['name' => $name, 'parent_location_id' => $node->getKey()]);
        }

        $this->assertSame(6, $this->storedDepth($node));

        $this->expectException(RuntimeException::class);

        // Six is the deepest LEGAL depth because a root is 0, so this is the seventh tier.
        Location::create(['name' => 'Fazla', 'parent_location_id' => $node->getKey()]);
    }

    public function test_a_moved_subtree_cannot_be_grafted_past_the_depth_cap(): void
    {
        $node = $this->shelf;

        foreach (['Kutu', 'Çekmece'] as $name) {
            $node = Location::create(['name' => $name, 'parent_location_id' => $node->getKey()]);
        }

        $deep = Location::create(['name' => 'A']);
        foreach (['B', 'C', 'D'] as $name) {
            $deep = Location::create(['name' => $name, 'parent_location_id' => $deep->getKey()]);
        }

        // The hole the descendant cascade opens if it is not checked: the moved node itself lands at a
        // legal depth while its subtree is pushed past 6. Without this the cap holds only for rows
        // someone touched directly.
        try {
            $this->fridge->update(['parent_location_id' => $deep->getKey()]);
            $this->fail('A move that pushes a descendant past the depth cap should be refused.');
        } catch (RuntimeException) {
            // Expected. What matters is the state afterwards.
        }

        // Rolled back, not half-applied. This is the assertion that earns the transaction wrapper: the
        // descendant's cap check throws AFTER this row's own update has been written, so without the
        // wrapper the move would stand and the subtree below it would keep the paths of its old parent.
        // A partially rewritten `path` column is indistinguishable from a correct one.
        $this->assertSame('/Mutfak/Buzdolabı/', $this->storedPath($this->fridge));
        $this->assertSame(1, $this->storedDepth($this->fridge));
        $this->assertSame('/Mutfak/Buzdolabı/Üst Raf/Kutu/Çekmece/', $this->storedPath($node));
    }
}
