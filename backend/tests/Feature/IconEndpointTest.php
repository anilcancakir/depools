<?php

namespace Tests\Feature;

use App\Models\Team;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * What a client is answered when it asks for icons.
 *
 * The catalogue itself is covered by `IconCatalogueTest`; this is about the endpoint's shape, its
 * bounds, and the one property that would look like a mistake to a reader of every other test here:
 * two tenants are answered the same rows on purpose.
 */
final class IconEndpointTest extends TestCase
{
    use RefreshDatabase;

    private function actAsSomeone(string $email = 'a@example.com'): User
    {
        /** @var User $user */
        $user = User::factory()->createOne(['email' => $email, 'locale' => 'en']);
        $team = Team::create(['name' => 'Alpha', 'user_id' => $user->getKey()]);
        $user->forceFill(['current_team_id' => $team->getKey()])->save();

        $this->actingAs($user->refresh(), 'sanctum');

        return $user;
    }

    public function test_a_search_answers_the_obvious_icon_first(): void
    {
        $this->actAsSomeone();

        $body = $this->getJson('/api/v1/icons?q=home')->assertOk()->json('data');

        $this->assertSame('home', $body[0]['name']);
        $this->assertStringStartsWith('<svg', $body[0]['svg']);
    }

    public function test_a_search_reaches_an_icon_through_its_tags(): void
    {
        // The reason the tags are stored at all: Material has no icon named `fridge`, and the glyph
        // the user means is `kitchen`.
        $this->actAsSomeone();

        $names = array_column($this->getJson('/api/v1/icons?q=fridge')->assertOk()->json('data'), 'name');

        $this->assertContains('kitchen', $names);
    }

    public function test_a_search_is_bounded(): void
    {
        // An empty query is a real request: the picker shows something before the user types. It has
        // to be the popular end of 4,185 rather than all of them.
        $this->actAsSomeone();

        $body = $this->getJson('/api/v1/icons')->assertOk()->json('data');

        $this->assertCount(50, $body);
    }

    public function test_a_batch_answers_exactly_the_names_asked_for(): void
    {
        $this->actAsSomeone();

        $body = $this->getJson('/api/v1/icons?names[]=kitchen&names[]=shelves')->assertOk()->json('data');

        $this->assertSame(['kitchen', 'shelves'], array_column($body, 'name'));
    }

    public function test_a_batch_ignores_a_name_that_does_not_exist_rather_than_failing(): void
    {
        // A client asking for an icon the catalogue lost after a re-vendor should still get the rest
        // of the screen. The missing one renders the fallback, which is what a null name does too.
        $this->actAsSomeone();

        $body = $this->getJson('/api/v1/icons?names[]=kitchen&names[]=not_a_real_glyph')
            ->assertOk()
            ->json('data');

        $this->assertSame(['kitchen'], array_column($body, 'name'));
    }

    public function test_an_oversized_batch_is_refused(): void
    {
        // The names come from a query string, so an unbounded `whereIn` is a way to ask for the whole
        // table one request at a time.
        $this->actAsSomeone();

        $this->getJson('/api/v1/icons?'.http_build_query(['names' => array_fill(0, 101, 'home')]))
            ->assertStatus(422)
            ->assertJsonValidationErrors('names');
    }

    public function test_two_tenants_are_answered_the_same_rows(): void
    {
        // **The opposite of the isolation test every other endpoint here carries, and deliberately
        // so.** The catalogue is global: `Icon` has no `team_id` and no `TeamScope`. Asserted rather
        // than left implicit, because a reader who knows this codebase would otherwise read the
        // missing scope as an oversight.
        $this->actAsSomeone('one@example.com');
        $first = $this->getJson('/api/v1/icons?q=warehouse')->assertOk()->json('data');

        $this->actAsSomeone('two@example.com');
        $second = $this->getJson('/api/v1/icons?q=warehouse')->assertOk()->json('data');

        $this->assertSame($first, $second);
        $this->assertNotEmpty($first);
    }

    public function test_the_catalogue_needs_authentication(): void
    {
        // Nothing here is one tenant's secret, but there is no reason to serve 4 MB of glyphs to
        // anyone who asks.
        $this->getJson('/api/v1/icons?q=home')->assertUnauthorized();
    }
}
