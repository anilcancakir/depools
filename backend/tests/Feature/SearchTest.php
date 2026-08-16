<?php

namespace Tests\Feature;

use App\Models\Location;
use App\Models\Product;
use App\Models\Team;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Testing\TestResponse;
use Tests\TestCase;

/**
 * One box, two kinds of answer.
 *
 * The product half reuses `ProductListQuery`, so what it means for a product to match is tested
 * where that lives. What is tested here is the seam: that both halves come back from one request,
 * that the location half searches the PATH rather than the leaf, and that a search box cannot be
 * used as a way to ask for everything.
 */
final class SearchTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();

        /** @var User $user */
        $user = User::factory()->createOne(['locale' => 'en']);
        $team = Team::create(['name' => 'Alpha', 'user_id' => $user->getKey()]);
        $user->forceFill(['current_team_id' => $team->getKey()])->save();

        $this->actingAs($user->refresh(), 'sanctum');
    }

    private function search(string $query): TestResponse
    {
        return $this->getJson('/api/v1/search?q='.urlencode($query));
    }

    public function test_one_request_answers_both_halves(): void
    {
        Product::create(['name' => 'Kırmızı biber', 'base_unit' => 'C62']);
        Location::create(['name' => 'Biberlik']);

        $this->search('biber')->assertOk()
            ->assertJsonCount(1, 'data.products')
            ->assertJsonCount(1, 'data.locations');
    }

    public function test_a_location_is_found_by_its_path_and_not_only_its_leaf(): void
    {
        // A user describes where something is by the route to it, so "kiler raf" has to find
        // `Kiler › Raf 1`. Searching the leaf alone would answer nothing here.
        $pantry = Location::create(['name' => 'Kiler']);
        Location::create(['name' => 'Raf 1', 'parent_location_id' => $pantry->getKey()]);

        $this->search('Kiler')->assertOk()->assertJsonCount(2, 'data.locations');

        $this->search('Raf')->assertOk()
            ->assertJsonCount(1, 'data.locations')
            ->assertJsonPath('data.locations.0.name', 'Raf 1');

        // **The multi-word case, which is the one the separator decides.** The column joins with
        // `/`, so without normalising it this query matches nothing at all: the user types the route
        // the way the screen shows it, with spaces.
        $this->search('kiler raf')->assertOk()
            ->assertJsonCount(1, 'data.locations')
            ->assertJsonPath('data.locations.0.name', 'Raf 1');
    }

    public function test_the_match_ignores_case(): void
    {
        Location::create(['name' => 'Depo']);

        $this->search('depo')->assertOk()->assertJsonCount(1, 'data.locations');
        $this->search('DEPO')->assertOk()->assertJsonCount(1, 'data.locations');
    }

    public function test_a_wildcard_does_not_answer_everything(): void
    {
        // `%` and `_` are LIKE wildcards and this needle comes from a search box. The same hole was
        // measured on the icon search, where `%` alone answered all 4,185 rows.
        Location::create(['name' => 'Depo']);
        Location::create(['name' => 'Mutfak']);

        $this->search('%')->assertOk()->assertJsonCount(0, 'data.locations');
        $this->search('_')->assertOk()->assertJsonCount(0, 'data.locations');
    }

    public function test_a_blank_query_is_refused_rather_than_answering_the_catalogue(): void
    {
        // A stray keystroke must not become the most expensive request in the app.
        Product::create(['name' => 'Süt', 'base_unit' => 'C62']);

        $this->getJson('/api/v1/search')->assertStatus(422)->assertJsonValidationErrors('q');
    }

    public function test_whitespace_is_the_same_as_blank(): void
    {
        // `TrimStrings` and `ConvertEmptyStringsToNull` turn a space into null before validation, so
        // this is the required rule firing rather than a second code path. Pinned because it is
        // middleware that makes it true and nothing in the controller says so.
        Product::create(['name' => 'Süt', 'base_unit' => 'C62']);

        $this->getJson('/api/v1/search?q=%20')->assertStatus(422)->assertJsonValidationErrors('q');
    }

    public function test_another_tenants_rows_are_not_in_the_answer(): void
    {
        Product::create(['name' => 'Süt', 'base_unit' => 'C62']);
        Location::create(['name' => 'Mutfak']);

        /** @var User $other */
        $other = User::factory()->createOne();
        $team = Team::create(['name' => 'Beta', 'user_id' => $other->getKey()]);
        $other->forceFill(['current_team_id' => $team->getKey()])->save();
        $this->actingAs($other->refresh(), 'sanctum');

        $this->search('u')->assertOk()
            ->assertJsonCount(0, 'data.products')
            ->assertJsonCount(0, 'data.locations');
    }

    public function test_it_is_behind_the_session(): void
    {
        $this->app->get('auth')->forgetGuards();

        $this->getJson('/api/v1/search?q=x')->assertUnauthorized();
    }
}
