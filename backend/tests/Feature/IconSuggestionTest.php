<?php

namespace Tests\Feature;

use App\Ai\Contracts\ModelCaller;
use App\Ai\CreditLedger;
use App\Models\AiCreditGrant;
use App\Models\AiUsageEvent;
use App\Models\Icon;
use App\Models\Team;
use App\Models\User;
use App\Services\IconSuggester;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Http;
use Illuminate\Testing\TestResponse;
use RuntimeException;
use Tests\Support\FakeModelCaller;
use Tests\TestCase;

/**
 * Choosing a location's icon from its name, without the user opening the picker.
 *
 * Driven through the HTTP endpoint and the real gateway rather than against [IconSuggester] alone,
 * because "no code path calls a model outside a gateway" is the property under test and a suggester
 * exercised with a stub gateway would say nothing about it. The MVP's icon endpoint is the reason
 * that rule exists.
 *
 * **Against the REAL catalogue, all 4,185 rows of it**, because the migration seeds them and
 * `RefreshDatabase` therefore hands every test the shipped vocabulary. Inventing three icons here
 * would have tested the lookup against a world designed to make it work, and the interesting half of
 * this feature is exactly what a general-purpose icon set does and does not contain. Every expected
 * name below was measured against that table rather than guessed.
 */
final class IconSuggestionTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();

        // Beside `AI_LIVE=false` in phpunit.xml: this turns the kill switch back on, so the fake
        // binding below is the only thing between a mistake and a live provider. This makes that
        // mistake a failure naming the URL.
        Http::preventStrayRequests();

        config(['ai_gateways.live' => true]);

        /** @var User $user */
        $user = User::factory()->createOne();
        $team = Team::create(['name' => 'Alpha', 'user_id' => $user->getKey()]);
        $user->forceFill(['current_team_id' => $team->getKey()])->save();

        $this->actingAs($user->refresh(), 'sanctum');

        AiCreditGrant::create([
            'kind' => 'plan_allowance',
            'credits' => 10,
            'period_start' => Carbon::now()->startOfMonth(),
            'expires_at' => Carbon::now()->endOfMonth(),
        ]);
    }

    /**
     * @param  list<array<string, mixed>|RuntimeException>  $script
     */
    private function model(array $script): FakeModelCaller
    {
        $caller = new FakeModelCaller($script);

        $this->app->instance(ModelCaller::class, $caller);

        return $caller;
    }

    private function suggest(string $name): TestResponse
    {
        return $this->postJson('/api/v1/icons/suggest', ['name' => $name]);
    }

    public function test_a_turkish_name_reaches_the_icon_its_english_word_names(): void
    {
        // The whole feature in one case, and the measurement behind it: `Buzdolabı` matches nothing
        // in a catalogue tagged in English, because no icon set anywhere publishes Turkish tags. The
        // model's only job is the language.
        $this->assertNull(Icon::matching('Buzdolabı')->first());

        $this->model([['terms' => ['refrigerator'], 'confidence' => 0.95]]);

        $this->suggest('Buzdolabı')
            ->assertOk()
            ->assertJsonPath('data.icon.name', 'kitchen')
            // The svg travels, because the form draws the suggestion straight away and a second
            // round trip to fetch it would show the neutral icon first and then swap it.
            ->assertJsonPath('data.icon.svg', Icon::query()->where('name', 'kitchen')->value('svg'));
    }

    public function test_the_first_term_that_matches_wins_rather_than_the_most_popular(): void
    {
        // **Why the terms keep the model's order instead of being pooled and ranked together.**
        // Measured on the shipped catalogue: `cupboard` answers `door_sliding` at popularity 395,
        // `kitchen` answers `kitchen` at 1576. Pooling both terms' matches and taking the most
        // popular would hand back the room for a name whose specific word names the furniture.
        $this->assertSame('door_sliding', Icon::matching('cupboard')->value('name'));
        $this->assertSame('kitchen', Icon::matching('kitchen')->value('name'));
        $this->assertGreaterThan(
            (int) Icon::query()->where('name', 'door_sliding')->value('popularity'),
            (int) Icon::query()->where('name', 'kitchen')->value('popularity'),
        );

        $this->model([['terms' => ['cupboard', 'kitchen'], 'confidence' => 0.9]]);

        $this->suggest('Mutfak dolabı')
            ->assertOk()
            ->assertJsonPath('data.icon.name', 'door_sliding');
    }

    public function test_a_later_term_answers_when_the_catalogue_lacks_the_first(): void
    {
        // The list is a fallback chain, which is what makes a general term worth returning at all.
        // `attic` is in no icon's text; `stairs` is.
        $this->assertNull(Icon::matching('attic')->first());

        $this->model([['terms' => ['attic', 'stairs'], 'confidence' => 0.85]]);

        $this->suggest('Tavan arası')
            ->assertOk()
            ->assertJsonPath('data.icon.name', 'stairs');
    }

    public function test_a_name_the_model_is_unsure_of_gets_nothing(): void
    {
        // **The half that matters.** `Raf 3` describes no object, and every name resolves to SOME
        // glyph if you let it: `shelf` answers `shelves` perfectly well. A confidently wrong default
        // is worse than none, because the user accepts a picture they did not read and the tree then
        // contradicts its own label.
        $this->assertSame('shelves', Icon::matching('shelf')->value('name'));

        $this->model([['terms' => ['shelf'], 'confidence' => 0.2]]);

        $this->suggest('Raf 3')
            ->assertOk()
            ->assertJsonPath('data.icon', null);
    }

    public function test_the_threshold_is_a_floor_rather_than_a_ceiling(): void
    {
        // Exactly at the line is an answer, not a refusal. Written down because an off-by-one on a
        // comparison here is invisible: both readings produce a plausible screen.
        $this->model([['terms' => ['garage'], 'confidence' => IconSuggester::MIN_CONFIDENCE]]);

        $this->suggest('Garaj')
            ->assertOk()
            ->assertJsonPath('data.icon.name', 'garage');
    }

    public function test_a_confident_answer_matching_nothing_gets_nothing(): void
    {
        // The second way to get null, and it is a vocabulary gap in a general-purpose icon set
        // rather than a bad read of the name. Same answer either way: the neutral icon.
        $this->model([['terms' => ['attic', 'loft'], 'confidence' => 0.95]]);

        $this->suggest('Tavan arası')
            ->assertOk()
            ->assertJsonPath('data.icon', null);
    }

    public function test_a_term_the_model_capitalised_still_matches(): void
    {
        // `search_text` is lowercase, so one stray capital narrows the match to nothing. Normalised
        // in the gateway rather than asked for in the prompt, because rule 1 is the rule models
        // break.
        //
        // **Casing and surrounding space are all this recovers.** A model that splits a word ("ware
        // house") is not rescued by collapsing the gap: that is a two-word query, both words are
        // substrings of `warehouse`, and it answers `inventory_2` because popularity decides between
        // the several icons whose text contains both. Measured, and left as a limit rather than
        // papered over: guessing which of a model's spaces were meant is how a lookup starts
        // inventing answers.
        $this->model([['terms' => ['  Warehouse  '], 'confidence' => 0.9]]);

        $this->suggest('Depo')
            ->assertOk()
            ->assertJsonPath('data.icon.name', 'warehouse');
    }

    public function test_the_model_never_names_an_icon_and_a_name_it_invented_is_not_one(): void
    {
        // **The division `AGENTS.md` draws, as a test.** A model asked for an icon would answer with
        // a plausible identifier that does not exist, and nothing in the response would say so. Here
        // it answers words, and a word nobody tagged is simply a word that matches nothing.
        $this->model([['terms' => ['freezer_outlined'], 'confidence' => 0.99]]);

        $this->suggest('Derin dondurucu')
            ->assertOk()
            ->assertJsonPath('data.icon', null);
    }

    public function test_an_answer_with_no_confidence_is_a_schema_failure(): void
    {
        // A suggestion that cannot be thresholded is the confidently wrong glyph this feature exists
        // to avoid, so it goes back to the runner as unusable and the next chain entry is asked more
        // strictly. Both entries failing is a null answer, not an error.
        $caller = $this->model([
            ['terms' => ['garage']],
            ['terms' => ['garage']],
        ]);

        $this->suggest('Garaj')->assertOk()->assertJsonPath('data.icon', null);

        $this->assertCount(2, $caller->calls);
        $this->assertStringContainsString('did not match the required schema', $caller->calls[1]['instructions']);
    }

    public function test_the_kill_switch_answers_null_without_calling_anything(): void
    {
        // `legal-and-privacy.md`'s switch, and the promise around it: every gateway degrades to its
        // manual path rather than erroring, so the form still opens with the neutral icon.
        config(['ai_gateways.live' => false]);

        $caller = $this->model([['terms' => ['garage'], 'confidence' => 0.9]]);

        $this->suggest('Garaj')->assertOk()->assertJsonPath('data.icon', null);

        $this->assertSame([], $caller->calls);
    }

    public function test_a_suggestion_spends_a_credit_and_leaves_a_usage_row(): void
    {
        // The reason this goes through a gateway at all: the MVP's icon endpoint called a model
        // directly and escaped the quota system entirely.
        $this->model([['terms' => ['garage'], 'confidence' => 0.9]]);

        $this->suggest('Garaj')->assertOk();

        $this->assertSame(1, AiUsageEvent::query()->where('outcome', 'succeeded')->count());
        $this->assertSame(9, app(CreditLedger::class)->balance());
    }

    public function test_a_tenant_with_no_credit_gets_nothing_rather_than_an_error(): void
    {
        AiCreditGrant::query()->delete();

        $caller = $this->model([['terms' => ['garage'], 'confidence' => 0.9]]);

        $this->suggest('Garaj')->assertOk()->assertJsonPath('data.icon', null);

        $this->assertSame([], $caller->calls);
        // Recorded even though nothing left the process: "this tenant is hitting their limit" is the
        // most actionable usage fact there is, and a declined action leaving no row hides it.
        $this->assertSame(1, AiUsageEvent::query()->where('outcome', 'no_credit')->count());
    }

    public function test_the_name_never_reaches_a_model_unauthenticated(): void
    {
        // The route has to be inside the authenticated group, and a route file is exactly where that
        // is easy to get wrong by one indentation level.
        Auth::forgetGuards();

        $caller = $this->model([['terms' => ['garage'], 'confidence' => 0.9]]);

        $this->postJson('/api/v1/icons/suggest', ['name' => 'Garaj'])->assertUnauthorized();

        $this->assertSame([], $caller->calls);
    }

    public function test_a_name_is_required(): void
    {
        $this->suggest('')->assertStatus(422)->assertJsonValidationErrors('name');
    }
}
