<?php

namespace Tests\Feature;

use App\Models\Location;
use App\Models\Team;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use RuntimeException;
use Tests\TestCase;

/**
 * Tenancy and hierarchy invariants for `locations`.
 *
 * `docs/depools-system/data-model.md` says these tests are written BEFORE the feature rather than
 * after, and the reason is in the same paragraph: a tenant scope that silently stops applying is
 * invisible from inside the application. Every screen still works, every list still fills, and the
 * rows are somebody else's. Asana shipped that exact shape in 2025 and it went unnoticed for over
 * a month.
 *
 * So the assertions here are deliberately blunt. They do not check that a filter was applied, they
 * check that another tenant's row cannot be seen, cannot be counted, and cannot be fetched by an
 * identifier the attacker already holds.
 */
final class LocationTenancyTest extends TestCase
{
    use RefreshDatabase;

    /**
     * A team with an owner, in that dependency order.
     *
     * `teams.user_id` is a real foreign key, so the owner has to exist before the team does, and
     * the user's `current_team_id` only afterwards. Writing it the other way round is what the
     * first run of this file did, and every test failed on the constraint rather than on tenancy,
     * which is the right way for a harness bug to announce itself.
     *
     * @return array{0: Team, 1: User}
     */
    private function tenant(string $name): array
    {
        $user = User::factory()->create();

        $team = Team::create(['name' => $name, 'user_id' => $user->getKey()]);

        $user->forceFill(['current_team_id' => $team->getKey()])->save();

        return [$team, $user->refresh()];
    }

    public function test_a_tenant_cannot_read_another_tenants_locations(): void
    {
        [, $first] = $this->tenant('Birinci');
        [, $second] = $this->tenant('İkinci');

        $this->actingAs($first);
        $mine = Location::create(['name' => 'Mutfak']);

        $this->actingAs($second);

        // Not "returns 403" and not "is filtered out of a list": it does not exist. A controller
        // reaching for it answers 404, which is tenancy rule 2, because a 403 would confirm the
        // identifier is real and let a tenant enumerate another tenant's rows one request at a time.
        $this->assertNull(Location::find($mine->getKey()));
        $this->assertSame(0, Location::count());
    }

    public function test_a_write_is_stamped_from_the_auth_context_and_not_from_input(): void
    {
        [$firstTeam, $first] = $this->tenant('Birinci');
        [$secondTeam] = $this->tenant('İkinci');

        $this->actingAs($first);

        // The attacker's move: supply the other tenant's id as ordinary input. `create` fills only
        // what `$fillable` allows, and `team_id` is deliberately absent from it, so the value is
        // dropped and the scope stamps the authenticated team instead.
        $location = Location::create(['name' => 'Depo', 'team_id' => $secondTeam->getKey()]);

        $this->assertSame($firstTeam->getKey(), $location->team_id);
    }

    public function test_an_unauthenticated_query_returns_nothing_rather_than_everything(): void
    {
        [, $first] = $this->tenant('Birinci');
        $this->actingAs($first);
        Location::create(['name' => 'Mutfak']);

        $this->app['auth']->forgetGuards();

        // Failing closed. The alternative, skipping the constraint when there is no user, turns a
        // forgotten guard into a full-table read instead of an empty one.
        $this->assertSame(0, Location::count());
    }

    public function test_path_and_depth_are_maintained_on_write(): void
    {
        [, $user] = $this->tenant('Birinci');
        $this->actingAs($user);

        $root = Location::create(['name' => 'Mutfak']);
        $child = Location::create(['name' => 'Buzdolabı', 'parent_location_id' => $root->getKey()]);

        $this->assertSame(0, $root->depth);
        $this->assertSame(1, $child->depth);
        $this->assertSame('/Mutfak/Buzdolabı/', $child->path);
        $this->assertSame('Mutfak › Buzdolabı', $child->full_path);
    }

    public function test_a_hierarchy_deeper_than_the_cap_is_rejected(): void
    {
        [, $user] = $this->tenant('Birinci');
        $this->actingAs($user);

        $parent = null;

        // Depths 0 through MAX_DEPTH inclusive are legal, so the chain is built to the deepest
        // ALLOWED value first. Building one short of it is what the first version did, and it
        // asserted that a legal tree throws.
        for ($level = 0; $level <= Location::MAX_DEPTH; $level++) {
            $parent = Location::create([
                'name' => 'Seviye '.$level,
                'parent_location_id' => $parent?->getKey(),
            ]);
        }

        $this->expectException(RuntimeException::class);

        Location::create(['name' => 'Bir fazla', 'parent_location_id' => $parent->getKey()]);
    }

    public function test_a_location_cannot_be_placed_inside_its_own_child(): void
    {
        [, $user] = $this->tenant('Birinci');
        $this->actingAs($user);

        $root = Location::create(['name' => 'Mutfak']);
        $child = Location::create(['name' => 'Buzdolabı', 'parent_location_id' => $root->getKey()]);

        $this->expectException(RuntimeException::class);

        // The MVP's failure: this made the parent its own descendant and every subsequent read
        // walked the chain forever.
        $root->update(['parent_location_id' => $child->getKey()]);
    }
}
