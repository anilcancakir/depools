<?php

namespace Tests\Feature;

use App\Ai\Contracts\ModelCaller;
use App\Models\AiCreditGrant;
use App\Models\AiUsageEvent;
use App\Models\GlobalProduct;
use App\Models\ProductCategory;
use App\Models\Team;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Storage;
use Illuminate\Testing\TestResponse;
use Tests\Support\FakeModelCaller;
use Tests\Support\ReceiptImages;
use Tests\TestCase;

/**
 * Reading a photographed product into the draft card the user is about to edit.
 *
 * Driven through the HTTP endpoint rather than against the service, because the properties worth
 * protecting are about what the CLIENT sees: that running out of credits is a 200 the screen can
 * explain rather than an error it cannot, and that a category the model invented never reaches it.
 *
 * **The fixtures are the receipt ones and that is deliberate.** The model is faked, so what the
 * picture shows is read by nothing: what the fixture has to provide is a decodable JPEG whose
 * perceptual hash is stable across two calls, which is exactly what it was built for. A synthetic
 * "product photograph" would be a second drawing routine that no assertion could tell from this one.
 */
final class ProductRecogniseTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();

        // Beside `AI_LIVE=false` in phpunit.xml: these tests turn the kill switch back on, so a
        // mistake reaching a provider becomes a failure naming the URL rather than a live call.
        Http::preventStrayRequests();
        Storage::fake('local');

        config(['ai_gateways.live' => true]);
    }

    public function test_a_photograph_reaches_the_model_as_an_image_rather_than_as_text(): void
    {
        $this->tenant();
        $this->credits(5);
        $caller = $this->model([$this->answer()]);

        $this->postPhoto()->assertOk();

        $this->assertCount(1, $caller->calls);
        $this->assertNotNull(
            $caller->calls[0]['image'],
            'the photograph travels as an image; describing it in the prompt would be a different feature',
        );
        $this->assertSame('image/jpeg', $caller->calls[0]['image']->mimeType);
    }

    public function test_the_card_carries_what_the_model_read(): void
    {
        $this->tenant();
        $this->credits(5);
        $this->model([$this->answer()]);

        $this->postPhoto()
            ->assertOk()
            ->assertJsonPath('data.found', true)
            ->assertJsonPath('data.cached', false)
            ->assertJsonPath('data.outcome', 'succeeded')
            ->assertJsonPath('data.name', 'Süt Tam Yağlı 1 L')
            ->assertJsonPath('data.brand', 'Pınar');
    }

    public function test_the_photograph_is_hashed_even_when_nothing_was_recognised(): void
    {
        $this->tenant();
        $this->credits(5);
        // Two entries in the chain, so the runner's stricter retry has somewhere to go and both
        // attempts have to be scripted.
        $this->model([$this->answer(['name' => null]), $this->answer(['name' => null])]);

        $response = $this->postPhoto()->assertOk()->assertJsonPath('data.found', false);

        // The hash is what a hand-typed card sends back so the next photograph of the same box is
        // free, so a failed read still has to carry one.
        $this->assertMatchesRegularExpression('/^[0-9a-f]{32}$/', $response->json('data.image_phash'));
    }

    public function test_a_category_the_taxonomy_does_not_carry_is_dropped(): void
    {
        $this->tenant();
        $this->credits(5);
        $this->model([$this->answer(['category' => 'artisanal moon cheese'])]);

        $this->postPhoto()
            ->assertOk()
            ->assertJsonPath('data.found', true)
            ->assertJsonPath('data.category_id', null)
            ->assertJsonPath('data.category_label', null);
    }

    public function test_a_category_the_taxonomy_carries_resolves(): void
    {
        $this->tenant();
        $this->credits(5);
        $this->model([$this->answer(['category' => 'milk'])]);

        // The seeded Google taxonomy, not a row this test made. A fixture taxonomy would let the
        // matching pass against a vocabulary the product does not have, which is the shape of test
        // that certifies itself.
        $this->postPhoto()
            ->assertOk()
            ->assertJsonPath('data.category_id', $this->seeded('Milk')->getKey())
            ->assertJsonPath('data.category_label', 'Milk');
    }

    public function test_a_category_named_by_one_part_of_a_compound_resolves(): void
    {
        $this->tenant();
        $this->credits(5);
        // The seeded Google taxonomy is full of these: `Tea & Infusions`, `Pasta & Noodles`,
        // `Candy & Chocolate`. A model answering with the ordinary word for the product is answering
        // correctly, and an exact whole-name match alone would drop every one of them.
        $this->model([$this->answer(['category' => 'tea'])]);

        $this->postPhoto()
            ->assertOk()
            ->assertJsonPath('data.category_id', $this->seeded('Tea & Infusions')->getKey());
    }

    public function test_a_name_that_merely_contains_the_phrase_is_not_a_match(): void
    {
        $this->tenant();
        $this->credits(5);
        // `board` appears inside `Breadboards` and inside `Cutting Boards`, and is a part of
        // neither: the compound pass compares whole parts for equality rather than searching inside
        // them, which is what stops it from being a fuzzy match wearing a different name.
        $this->model([$this->answer(['category' => 'board'])]);

        $this->postPhoto()->assertOk()->assertJsonPath('data.category_id', null);
    }

    public function test_a_unit_word_outside_the_vocabulary_is_dropped(): void
    {
        $this->tenant();
        $this->credits(5);
        // A model reading "500 g" off a bag will answer in grams, which describes the CONTENTS and
        // not what a person counts. `UnitHint` has no gram in it, so this arrives as null rather
        // than as a base unit that makes a 500 g pack read as "2 g" on the count sheet.
        $this->model([$this->answer(['unit' => 'gram'])]);

        $this->postPhoto()->assertOk()->assertJsonPath('data.unit', null);
    }

    public function test_a_unit_word_inside_the_vocabulary_becomes_its_rec_20_code(): void
    {
        $this->tenant();
        $this->credits(5);
        $this->model([$this->answer(['unit' => 'piece'])]);

        $this->postPhoto()->assertOk()->assertJsonPath('data.unit', 'C62');
    }

    public function test_a_weighed_category_supplies_the_unit_the_model_could_not(): void
    {
        $this->tenant();
        $this->credits(5);
        $this->model([$this->answer(['category' => 'fruits', 'unit' => null])]);

        // A greengrocer's tomatoes are kilograms whatever the photograph looks like, and the
        // taxonomy already knows which of its branches are weighed.
        $this->postPhoto()->assertOk()->assertJsonPath('data.unit', 'KGM');
    }

    public function test_running_out_of_credits_answers_200_with_the_reason(): void
    {
        $this->tenant();
        // No grant at all. `credits(0)` would violate `ai_credit_grants_credits_are_positive`.
        $caller = $this->model([]);

        $this->postPhoto()
            ->assertOk()
            ->assertJsonPath('data.found', false)
            ->assertJsonPath('data.outcome', 'no_credit');

        $this->assertCount(0, $caller->calls, 'no credit means no provider is reached at all');
    }

    public function test_the_kill_switch_leaves_the_manual_path_open(): void
    {
        $this->tenant();
        $this->credits(5);
        $caller = $this->model([]);

        config(['ai_gateways.live' => false]);

        // 200 and not an error: `ai-enrichment.md` requires manual creation to stay fully functional,
        // and a 4xx here would make the screen treat a deliberate setting as a fault.
        $this->postPhoto()->assertOk()->assertJsonPath('data.found', false);

        $this->assertCount(0, $caller->calls);
    }

    public function test_a_read_writes_nothing_to_the_shared_catalogue(): void
    {
        $this->tenant();
        $this->credits(5);
        $this->model([$this->answer()]);

        $this->postPhoto()->assertOk();

        // Anılcan's call: the catalogue gains a row when the user SAVES the card, not when a model
        // answers, so what other tenants read is always something a person looked at.
        $this->assertSame(0, GlobalProduct::query()->count());
    }

    public function test_a_saved_card_makes_the_same_photograph_free_the_next_time(): void
    {
        $this->tenant();
        $this->credits(5);
        $caller = $this->model([$this->answer()]);

        $first = $this->postPhoto()->assertOk();
        $phash = $first->json('data.image_phash');

        // The save is what fills the cache, through the ordinary create endpoint.
        $this->postJson('/api/v1/products', [
            'name' => 'Süt Tam Yağlı 1 L',
            'brand' => 'Pınar',
            'description' => 'Tam yağlı UHT süt.',
            'product_category_id' => $this->seeded('Milk')->getKey(),
            'image_phash' => $phash,
        ])->assertCreated();

        $this->assertSame($phash, GlobalProduct::query()->value('image_phash'));

        $second = $this->postPhoto()
            ->assertOk()
            ->assertJsonPath('data.cached', true)
            ->assertJsonPath('data.name', 'Süt Tam Yağlı 1 L')
            // **The description and the category come back too, and leaving them out made the cache
            // pointless.** Every row carrying a hash is written by the contribution path, so a hit
            // that dropped them would return strictly less than the model read it replaced.
            ->assertJsonPath('data.description', 'Tam yağlı UHT süt.')
            ->assertJsonPath('data.category_id', $this->seeded('Milk')->getKey())
            // Null rather than `succeeded`: nothing was asked of a model, and reporting an outcome
            // would put a call that never happened into the usage story.
            ->assertJsonPath('data.outcome', null);

        $this->assertSame($phash, $second->json('data.image_phash'));
        $this->assertCount(1, $caller->calls, 'the second read is answered by the catalogue');
        $this->assertSame(1, AiUsageEvent::query()->count(), 'and it costs no credit');
    }

    public function test_a_hash_this_tenant_never_read_is_not_spendable(): void
    {
        $this->tenant();

        // 32 valid hex characters that no photograph here ever produced. Without the token the
        // reader mints, this would bind an arbitrary hash to a shared catalogue row for every
        // tenant, first-come-first-served, with no camera involved.
        $this->postJson('/api/v1/products', [
            'name' => 'Süt Tam Yağlı 1 L',
            'image_phash' => str_repeat('c', 32),
        ])->assertCreated();

        $this->assertNull(GlobalProduct::query()->sole()->image_phash);
    }

    public function test_the_category_the_read_resolved_reaches_the_product(): void
    {
        $this->tenant();

        $milk = $this->seeded('Milk');

        $this->postJson('/api/v1/products', [
            'name' => 'Süt Tam Yağlı 1 L',
            'product_category_id' => $milk->getKey(),
        ])->assertCreated()->assertJsonPath('data.product_category_id', $milk->getKey());
    }

    public function test_another_tenants_category_is_refused(): void
    {
        $this->tenant();

        // The taxonomy is shared rows PLUS this tenant's own, so a bare `exists` rule would accept
        // a private category belonging to somebody else.
        // **`setAttribute` and not `create`, because `team_id` is never fillable.** Passing it to
        // `create` writes a null and produces a SHARED row, which would have made this test pass
        // for the wrong reason: it would be asserting that a shared category is accepted.
        $mine = new ProductCategory;
        $mine->setAttribute('team_id', Team::query()->sole()->getKey());
        $mine->fill(['name_en' => 'Workshop consumables', 'path' => 'Workshop consumables', 'depth' => 0]);
        $mine->save();

        $this->tenant('Beta');

        $this->postJson('/api/v1/products', [
            'name' => 'Süt Tam Yağlı 1 L',
            'product_category_id' => $mine->getKey(),
        ])->assertStatus(422)->assertJsonValidationErrors('product_category_id');
    }

    public function test_a_catalogue_row_in_another_locale_is_not_a_hit(): void
    {
        $this->tenant();
        $this->credits(5);
        $caller = $this->model([$this->answer(), $this->answer()]);

        $phash = $this->postPhoto()->assertOk()->json('data.image_phash');

        GlobalProduct::create([
            'name' => 'Whole Milk 1 L',
            'locale' => 'de',
            'source' => 'community',
            'image_phash' => $phash,
        ]);

        // The row describes the same object in a language this tenant does not read, so showing it
        // would be the wrong card. Translating it is the barcode path's job, not this one's.
        $this->postPhoto()->assertOk()->assertJsonPath('data.cached', false);

        $this->assertCount(2, $caller->calls);
    }

    public function test_a_file_that_is_not_an_image_is_refused(): void
    {
        $this->tenant();
        $this->credits(5);
        $this->model([]);

        $this->postJson('/api/v1/products/recognise', [
            'photo' => UploadedFile::fake()->create('notes.pdf', 12, 'application/pdf'),
        ])->assertStatus(422)->assertJsonValidationErrors('photo');
    }

    public function test_the_endpoint_is_behind_authentication(): void
    {
        $this->postJson('/api/v1/products/recognise', ['photo' => ReceiptImages::receiptA()])
            ->assertUnauthorized();
    }

    public function test_the_uploaded_photograph_is_kept_for_the_diagnostic_window(): void
    {
        $this->tenant();
        $this->credits(5);
        $this->model([$this->answer()]);

        config(['media.enrichment.keep_upload_days' => 14]);

        $this->postPhoto()->assertOk();

        $today = Carbon::now()->toDateString();
        $this->assertCount(1, Storage::disk('local')->files("enrichment/{$today}"));
    }

    public function test_nothing_is_kept_when_the_window_is_off(): void
    {
        $this->tenant();
        $this->credits(5);
        $this->model([$this->answer()]);

        config(['media.enrichment.keep_upload_days' => 0]);

        $this->postPhoto()->assertOk();

        $this->assertSame([], Storage::disk('local')->allFiles('enrichment'));
    }

    /**
     * A scripted model answer, with any field overridden.
     *
     * @param  array<string, mixed>  $overrides
     * @return array<string, mixed>
     */
    private function answer(array $overrides = []): array
    {
        return array_merge([
            'name' => 'Süt Tam Yağlı 1 L',
            'brand' => 'Pınar',
            'description' => 'Tam yağlı UHT süt.',
            'category' => null,
            'unit' => null,
        ], $overrides);
    }

    private function postPhoto(): TestResponse
    {
        return $this->postJson('/api/v1/products/recognise', ['photo' => ReceiptImages::receiptA()]);
    }

    private function model(array $script): FakeModelCaller
    {
        $caller = new FakeModelCaller($script);

        $this->app->instance(ModelCaller::class, $caller);

        return $caller;
    }

    /**
     * A row from the taxonomy the migration seeds, by its English name.
     *
     * `firstOrFail` rather than `first`: a rename upstream should fail the test that depends on the
     * name rather than silently compare an id against null.
     */
    private function seeded(string $nameEn): ProductCategory
    {
        return ProductCategory::query()->shared()->where('name_en', $nameEn)->firstOrFail();
    }

    private function tenant(): void
    {
        /** @var User $user */
        $user = User::factory()->createOne();
        $team = Team::create(['name' => 'Alpha', 'user_id' => $user->getKey()]);
        $user->forceFill(['current_team_id' => $team->getKey()])->save();
        $user->refresh();

        $this->actingAs($user, 'sanctum');
    }

    private function credits(int $credits): void
    {
        AiCreditGrant::create([
            'kind' => 'plan_allowance',
            'credits' => $credits,
            'period_start' => Carbon::now()->startOfMonth(),
            'expires_at' => Carbon::now()->endOfMonth(),
        ]);
    }
}
