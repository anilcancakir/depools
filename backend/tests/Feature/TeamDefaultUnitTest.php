<?php

namespace Tests\Feature;

use App\Models\Product;
use App\Models\Team;
use App\Models\Unit;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * The unit a product gets when nobody named one.
 *
 * Three steps, each narrower than the last: what the caller said, the team's own default, and
 * `Unit::fallback()` (`C62`, one piece). D29 and D32 call this inference; this is the layer of it
 * that does not need a taxonomy, which `product_categories` currently has zero rows of.
 */
final class TeamDefaultUnitTest extends TestCase
{
    use RefreshDatabase;

    private User $user;

    private Team $team;

    protected function setUp(): void
    {
        parent::setUp();

        /** @var User $user */
        $user = User::factory()->createOne(['locale' => 'en']);
        $team = Team::create(['name' => 'Alpha', 'user_id' => $user->getKey()]);
        $user->forceFill(['current_team_id' => $team->getKey()])->save();

        $this->user = $user->refresh();
        $this->team = $team->refresh();

        $this->actingAs($this->user, 'sanctum');
    }

    private function setDefault(string $code): void
    {
        $this->team->forceFill([
            'default_unit_id' => Unit::query()->where('code', $code)->value('id'),
        ])->save();
    }

    public function test_a_product_with_no_unit_falls_back_to_one_piece(): void
    {
        // The team has said nothing, so the vocabulary's own default applies. This is the behaviour
        // that already existed; it is here so the next two tests are read against it.
        $this->assertSame(Unit::DEFAULT_CODE, Product::create(['name' => 'Süt'])->unit->code);
    }

    public function test_the_teams_default_applies_when_the_caller_names_nothing(): void
    {
        $this->setDefault('KGM');

        $this->assertSame('KGM', Product::create(['name' => 'Un'])->unit->code);
    }

    public function test_what_the_caller_names_wins_over_the_teams_default(): void
    {
        // The chain narrows: a caller who said `LTR` meant it, whatever the team counts in usually.
        $this->setDefault('KGM');

        $this->assertSame('LTR', Product::create(['name' => 'Süt', 'base_unit' => 'LTR'])->unit->code);
    }

    public function test_the_default_applies_outside_a_request_too(): void
    {
        // **The reason this reads the PRODUCT's team rather than the auth context.** A seeder, a
        // queued import and a console command all reach `creating`, and `TeamScope::currentTeamId()`
        // answers null for every one of them, so a team-scoped lookup would silently skip the
        // default for exactly the callers that cannot pass a team any other way.
        $this->setDefault('KGM');

        $team = $this->team;
        $this->app['auth']->forgetGuards();

        $product = new Product(['name' => 'Un']);
        $product->setAttribute('team_id', $team->getKey());
        $product->save();

        $this->assertSame('KGM', $product->refresh()->unit->code);
    }

    public function test_the_endpoint_reads_and_writes_the_default_as_a_code(): void
    {
        // A CODE rather than an id, because everything else in this API speaks codes and a client
        // holding a uuid to name a unit would be the only place that does.
        $this->getJson('/api/v1/team/settings')
            ->assertOk()
            ->assertJsonPath('data.default_unit', null);

        $this->putJson('/api/v1/team/settings', ['default_unit' => 'KGM'])
            ->assertOk()
            ->assertJsonPath('data.default_unit', 'KGM');

        $this->assertSame('KGM', Product::create(['name' => 'Un'])->unit->code);
    }

    public function test_clearing_the_default_is_a_real_write_rather_than_no_change(): void
    {
        // `null` has to be accepted and STORED, because clearing is how a team goes back to the
        // vocabulary's fallback. Treating it as "no change" would make the setting one-way.
        $this->setDefault('KGM');

        $this->putJson('/api/v1/team/settings', ['default_unit' => null])
            ->assertOk()
            ->assertJsonPath('data.default_unit', null);

        $this->assertSame(Unit::DEFAULT_CODE, Product::create(['name' => 'Un'])->unit->code);
    }

    public function test_an_unknown_code_is_refused(): void
    {
        // Absent and wrong are different: one falls back, the other is a 422 naming the field.
        $this->putJson('/api/v1/team/settings', ['default_unit' => 'not-a-unit'])
            ->assertStatus(422)
            ->assertJsonValidationErrors('default_unit');
    }

    public function test_a_teams_default_does_not_reach_another_team(): void
    {
        $this->setDefault('KGM');

        /** @var User $other */
        $other = User::factory()->createOne(['email' => 'other@example.com', 'locale' => 'en']);
        $theirTeam = Team::create(['name' => 'Beta', 'user_id' => $other->getKey()]);
        $other->forceFill(['current_team_id' => $theirTeam->getKey()])->save();

        $this->actingAs($other->refresh(), 'sanctum');

        $this->getJson('/api/v1/team/settings')
            ->assertOk()
            ->assertJsonPath('data.default_unit', null);

        $this->assertSame(Unit::DEFAULT_CODE, Product::create(['name' => 'Un'])->unit->code);
    }
}
