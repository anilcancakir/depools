<?php

namespace Tests\Feature;

use App\Ai\Contracts\ModelCaller;
use App\Models\AiCreditGrant;
use App\Models\AiUsageEvent;
use App\Models\Barcode;
use App\Models\GlobalProduct;
use App\Models\OffProduct;
use App\Models\Product;
use App\Models\Team;
use App\Models\User;
use App\Support\Gtin;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Http;
use Tests\Support\FakeModelCaller;
use Tests\TestCase;

/**
 * The resolution cascade: what a scanned barcode is, as opposed to whether the tenant owns it.
 *
 * The stages are ordered by trust rather than by cost alone, so the assertions here are mostly about
 * ORDER: a product the tenant owns must win over a catalogue row describing the same thing, because
 * the tenant's own record is the only authoritative one and a catalogue row would overwrite a name
 * they chose with one somebody else did.
 *
 * Tenancy first, as `data-model.md` asks. It matters differently here than on `by-barcode`: this
 * endpoint is ALLOWED to answer about products the tenant does not own, since that is the whole point
 * of a catalogue. What it must never do is answer with another TENANT's product.
 */
final class BarcodeCascadeTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();

        // **No test may reach Open Food Facts, and this is the line that guarantees it.** Stage 3
        // falls through to a live lookup when the local table misses, so several cases here would
        // otherwise make a real request: slow, dependent on somebody else's uptime, and rate-limited
        // at 15 a minute for everyone sharing the IP. `preventStrayRequests` turns an unfaked call
        // into a failure naming the URL rather than into a mysteriously slow green run.
        //
        // No default stub beside it, deliberately. `Http::fake()` MERGES rather than replaces and the
        // first matching stub wins, so a default here would silently shadow every per-test one: two
        // of these tests passed a status-1 response and got the default's status-0 back. Each test
        // now declares what it expects to leave the building, and a test that expects nothing to
        // leave fails loudly if something does.
        Http::preventStrayRequests();
    }

    /** Open Food Facts answers with a product. */
    private function offReturns(array $product): void
    {
        Http::fake(['world.openfoodfacts.org/*' => Http::response([
            'status' => 1,
            'product' => $product,
        ], 200)]);
    }

    /** Open Food Facts answers that it has nothing, which is a 200 with `status: 0`. */
    private function offHasNothing(): void
    {
        Http::fake(['world.openfoodfacts.org/*' => Http::response(['status' => 0], 200)]);
    }

    /** @return array{0: User, 1: Team} */
    private function tenant(string $name): array
    {
        /** @var User $user */
        $user = User::factory()->createOne();
        $team = Team::create(['name' => $name, 'user_id' => $user->getKey()]);
        $user->forceFill(['current_team_id' => $team->getKey()])->save();
        $user->refresh();

        $this->actingAs($user, 'sanctum');

        return [$user, $team];
    }

    private function offRow(string $gtin, string $name): OffProduct
    {
        return OffProduct::create([
            'gtin' => $gtin,
            'name' => $name,
            'brand' => 'Off Brand',
            'locale' => 'en',
            // The code OFF issued, exactly as both writers now store it. A fixture that builds a row
            // the running system cannot produce is worse than no fixture: every test sharing it
            // certifies a world that does not exist, which is how the OFF stage in this very file was
            // unreachable in production while sixteen tests passed.
            'source_ref' => Gtin::fromScan($gtin)->toOpenFoodFacts(),
            'imported_at' => Carbon::now(),
        ]);
    }

    public function test_a_tenants_own_product_wins_over_every_catalogue(): void
    {
        // **The order is the assertion.** A catalogue row describing the same carton would overwrite
        // the name this tenant chose with the one somebody else chose, and their own record is the
        // only authoritative answer about their own inventory.
        $this->tenant('Alpha');

        $barcode = Barcode::forGtin('8690504010012');

        $mine = Product::create(['name' => 'My Own Milk', 'base_unit' => 'piece']);
        $mine->linkBarcode($barcode);

        $global = GlobalProduct::create([
            'name' => 'Community Milk',
            'locale' => 'en',
            'source' => 'community',
            'confidence' => 80,
        ]);
        $global->barcodes()->attach($barcode->getKey());

        $this->offRow('08690504010012', 'Open Food Facts Milk');

        $this->getJson('/api/v1/barcode/resolve?code=8690504010012')
            ->assertOk()
            ->assertJsonPath('data.source', 'own')
            ->assertJsonPath('data.name', 'My Own Milk')
            ->assertJsonPath('data.confidence', 100)
            ->assertJsonPath('data.product_id', $mine->getKey());
    }

    public function test_the_community_catalogue_answers_when_the_tenant_does_not_own_it(): void
    {
        $this->tenant('Alpha');

        $barcode = Barcode::forGtin('8690504010012');

        $global = GlobalProduct::create([
            'name' => 'Community Milk',
            'brand' => 'Pınar',
            'locale' => 'tr',
            'source' => 'community',
            'confidence' => 80,
        ]);
        $global->barcodes()->attach($barcode->getKey());

        $this->getJson('/api/v1/barcode/resolve?code=8690504010012')
            ->assertOk()
            ->assertJsonPath('data.source', 'community')
            ->assertJsonPath('data.name', 'Community Milk')
            ->assertJsonPath('data.product_id', null)
            // Contributable, because a community row is already in the shared catalogue: it carries
            // no licence that would stop another tenant confirming it.
            ->assertJsonPath('data.contributable', true);
    }

    public function test_open_food_facts_answers_last_and_is_never_contributable(): void
    {
        // **The licence, not the quality.** ODbL obliges a database combined with OFF data to be
        // released as open data, so an OFF-derived row must not move into the shared catalogue. The
        // flag is what carries that to the contribution path, which cannot see where the row came
        // from otherwise.
        $this->tenant('Alpha');

        Barcode::forGtin('8690504010012');
        $this->offRow('08690504010012', 'Open Food Facts Milk');

        $this->getJson('/api/v1/barcode/resolve?code=8690504010012')
            ->assertOk()
            ->assertJsonPath('data.source', 'off')
            ->assertJsonPath('data.name', 'Open Food Facts Milk')
            ->assertJsonPath('data.contributable', false);
    }

    public function test_another_tenants_product_is_not_an_answer(): void
    {
        // This endpoint may answer about products the tenant does not own, which is what a catalogue
        // is for. It may never answer with another TENANT's product: that is their inventory, and the
        // barcode being global is exactly what makes the mistake reachable.
        $this->tenant('Beta');
        $theirs = Product::create(['name' => 'Beta Secret Milk', 'base_unit' => 'piece']);
        $theirs->linkBarcode(Barcode::forGtin('8690504010012'));

        $this->tenant('Alpha');

        // Own misses because the scope hides Beta's product, community has nothing, and the local
        // OFF table is empty, so this case genuinely reaches the live lookup.
        $this->offHasNothing();

        $this->getJson('/api/v1/barcode/resolve?code=8690504010012')
            ->assertNotFound();
    }

    public function test_a_code_nothing_carries_is_a_miss_rather_than_an_empty_candidate(): void
    {
        // Stage 6 is not code: the cascade having nothing to say is what sends the user to type it
        // in. An empty candidate would make the screen unable to tell that from a blank hit.
        $this->tenant('Alpha');

        $this->getJson('/api/v1/barcode/resolve?code=5060337502900')
            ->assertNotFound();
    }

    public function test_a_upc_and_an_ean_read_of_one_label_reach_the_same_catalogue_row(): void
    {
        $this->tenant('Alpha');

        Barcode::forGtin('614141999996');
        $this->offRow('00614141999996', 'Normalised Milk');

        $this->getJson('/api/v1/barcode/resolve?code=0614141999996')
            ->assertOk()
            ->assertJsonPath('data.name', 'Normalised Milk');
    }

    public function test_a_local_miss_asks_open_food_facts_once_and_keeps_the_answer(): void
    {
        // The top-up exists for the gap the bulk import cannot close: a product added to OFF after
        // the dump was taken. Storing the answer is the point of it, since that turns one user's
        // miss into everybody's hit and the second scan never leaves the building.
        $this->offReturns([
            'product_name' => 'Live Milk',
            'brands' => 'Live Brand',
            'lang' => 'tr',
        ]);

        $this->tenant('Alpha');
        Barcode::forGtin('8690504010012');

        $this->getJson('/api/v1/barcode/resolve?code=8690504010012')
            ->assertOk()
            ->assertJsonPath('data.source', 'off')
            ->assertJsonPath('data.name', 'Live Milk');

        $this->assertDatabaseHas('off_products', [
            'gtin' => '08690504010012',
            'name' => 'Live Milk',
            'locale' => 'tr',
        ]);

        // The stored row is what answers next time, so the second scan makes no request at all.

        $this->getJson('/api/v1/barcode/resolve?code=8690504010012')
            ->assertOk()
            ->assertJsonPath('data.name', 'Live Milk');
    }

    public function test_the_lookup_strips_our_padding_because_off_keys_on_thirteen(): void
    {
        // We hold GTIN-14 because GS1 says so; OFF pads to 13 and does not address 14, so asking it
        // for `08690504010012` misses a product it has under `8690504010012`.
        $this->offReturns(['product_name' => 'Live Milk', 'lang' => 'en']);

        $this->tenant('Alpha');
        Barcode::forGtin('8690504010012');

        $this->getJson('/api/v1/barcode/resolve?code=8690504010012')->assertOk();

        Http::assertSent(static fn ($request): bool => str_contains($request->url(), '/8690504010012'));
    }

    public function test_a_failing_lookup_is_a_miss_rather_than_an_error(): void
    {
        // **A user is holding a carton.** A timeout, a rate-limit answer or an outage all have to
        // read as "OFF does not have it", because an error here is one they cannot act on and the
        // next stage costs nothing. What it trades away is that a transient failure looks like a
        // miss for that one scan.
        Http::fake(['world.openfoodfacts.org/*' => Http::response('rate limited', 429)]);

        $this->tenant('Alpha');
        Barcode::forGtin('8690504010012');

        $this->getJson('/api/v1/barcode/resolve?code=8690504010012')->assertNotFound();
    }

    public function test_the_kill_switch_stops_the_lookup_leaving_the_building(): void
    {
        // `legal-and-privacy.md` asks every external source to be disableable without a deploy.
        config(['services.openfoodfacts.live' => false]);

        $this->tenant('Alpha');
        Barcode::forGtin('8690504010012');

        $this->getJson('/api/v1/barcode/resolve?code=8690504010012')->assertNotFound();

        Http::assertNothingSent();
    }

    public function test_a_gtin_nothing_here_has_ever_recorded_still_reaches_open_food_facts(): void
    {
        // **The case every other test in this file accidentally set up around.** They all call
        // `Barcode::forGtin()` first, which creates the row stages 1 and 2 link through, so they
        // verified a path that a real scan of a new product never takes. Stage 3 keys on the GTIN
        // itself, and it sat behind that row: the import and the top-up were unreachable in
        // production while the suite was green.
        $this->tenant('Alpha');

        $this->offRow('08690504010012', 'Never Seen Milk');

        $this->assertSame(0, Barcode::query()->count(), 'the point of this test is that no row exists');

        $this->getJson('/api/v1/barcode/resolve?code=8690504010012')
            ->assertOk()
            ->assertJsonPath('data.source', 'off')
            ->assertJsonPath('data.name', 'Never Seen Milk');
    }

    public function test_an_unrecorded_gtin_asks_open_food_facts_live(): void
    {
        // Same shape one layer out: with nothing local either, the top-up is the only thing that can
        // answer, and it could not be reached at all before.
        $this->offReturns(['product_name' => 'Live Unseen Milk', 'lang' => 'en']);

        $this->tenant('Alpha');

        $this->getJson('/api/v1/barcode/resolve?code=8690504010012')
            ->assertOk()
            ->assertJsonPath('data.name', 'Live Unseen Milk');
    }

    public function test_a_non_gtin_label_with_no_row_does_not_ask_open_food_facts(): void
    {
        // OFF keys on GTINs, so asking it about an internal Code128 shelf tag is a request that
        // cannot hit. It is a miss without leaving the building.
        $this->tenant('Alpha');

        $this->getJson('/api/v1/barcode/resolve?code=SHELF-A-0042&symbology=code128')
            ->assertNotFound();

        Http::assertNothingSent();
    }

    public function test_the_community_answer_is_in_the_users_own_locale(): void
    {
        // **One barcode names several rows, because the catalogue holds one per locale.** A bare
        // `first()` returned whichever the database offered, so the same scan could answer in Turkish
        // for one request and English for the next: a screen that looks broken rather than
        // multilingual.
        [$user] = $this->tenant('Alpha');
        $user->forceFill(['locale' => 'tr'])->save();

        $barcode = Barcode::forGtin('8690504010012');

        foreach ([['en', 'English Milk', 90], ['tr', 'Türk Sütü', 50]] as [$locale, $name, $confidence]) {
            $row = GlobalProduct::create([
                'name' => $name,
                'locale' => $locale,
                'source' => 'community',
                'confidence' => $confidence,
            ]);
            $row->barcodes()->attach($barcode->getKey());
        }

        // Turkish wins despite the LOWER confidence, because a product the user can read beats a
        // more-corroborated one they cannot.
        $this->getJson('/api/v1/barcode/resolve?code=8690504010012')
            ->assertOk()
            ->assertJsonPath('data.name', 'Türk Sütü');
    }

    public function test_a_locale_the_catalogue_lacks_still_gets_an_answer(): void
    {
        // A hit in another language beats no product at all, and filling the gap is what the
        // translation step will do once the AI gateway exists. Confidence decides among the rest.
        [$user] = $this->tenant('Alpha');
        $user->forceFill(['locale' => 'de'])->save();

        $barcode = Barcode::forGtin('8690504010012');

        foreach ([['en', 'Weak English', 40], ['fr', 'Strong French', 95]] as [$locale, $name, $confidence]) {
            $row = GlobalProduct::create([
                'name' => $name,
                'locale' => $locale,
                'source' => 'community',
                'confidence' => $confidence,
            ]);
            $row->barcodes()->attach($barcode->getKey());
        }

        $this->getJson('/api/v1/barcode/resolve?code=8690504010012')
            ->assertOk()
            ->assertJsonPath('data.name', 'Strong French');
    }

    public function test_a_live_answer_records_the_code_open_food_facts_answered_on(): void
    {
        // Same provenance rule as the bulk import: `source_ref` is the pointer a takedown is executed
        // against, so it holds the code OFF addressed the product by. The live path stored
        // `off:api:<gtin>` and `OffProduct::offCode()` then returned something OFF never issued.
        $this->offReturns(['product_name' => 'Live Milk', 'lang' => 'en']);

        $this->tenant('Alpha');
        Barcode::forGtin('8690504010012');

        $this->getJson('/api/v1/barcode/resolve?code=8690504010012')->assertOk();

        // The 13 OFF answered on, not our stored 14 and not a prefix.
        $this->assertSame('8690504010012', OffProduct::where('gtin', '08690504010012')->sole()->offCode());
    }

    public function test_an_unidentifiable_code_is_refused_rather_than_reported_as_unknown(): void
    {
        // **404 means "no source knows this product" and starts stage 6**, where the client offers to
        // create one carrying the code. A non-GTIN read with no symbology can never become that row,
        // because `Barcode::forCode()` takes the symbology as part of the identity: the same
        // characters as Code128 and as a QR are two different labels. Answering 404 would send the
        // user into a flow that cannot finish, so this is a 422 naming the field that is missing.
        $this->tenant('Alpha');

        $this->getJson('/api/v1/barcode/resolve?code=SHELF-A-0042')
            ->assertStatus(422)
            ->assertJsonValidationErrors('symbology');

        Http::assertNothingSent();
    }

    public function test_a_gtin_still_needs_no_symbology(): void
    {
        // The other half of the rule, and the one that would break first: a GTIN identifies itself,
        // so the refusal above must not reach the case that is 99% of scans. `test_a_non_gtin_label_
        // with_no_row_does_not_ask_open_food_facts` pins the third case, a non-GTIN that has one.
        $this->offHasNothing();

        $this->tenant('Alpha');

        // A miss, which is the point: it got past the refusal and through the whole cascade.
        $this->getJson('/api/v1/barcode/resolve?code=8690504010012')->assertNotFound();
    }

    public function test_a_foreign_catalogue_row_is_translated_and_written_back(): void
    {
        // **The gap this closes compounds.** Without the write-back, every Turkish scan of a French
        // contribution spends a credit and produces nothing durable; with it, the first scan pays and
        // every later one is free, instant and needs no model at all.
        $this->tenant('Alpha');
        config(['ai_gateways.live' => true]);
        AiCreditGrant::create(['kind' => 'plan_allowance', 'credits' => 10,
            'period_start' => Carbon::now()->startOfMonth(), 'expires_at' => Carbon::now()->endOfMonth()]);
        $this->app->instance(ModelCaller::class, new FakeModelCaller([
            ['name' => 'Yarım yağlı UHT süt 1L', 'brand' => 'Lactel', 'description' => 'UHT süt.'],
        ]));

        $barcode = Barcode::forGtin('8690504010012');
        $french = GlobalProduct::create([
            'name' => 'Lait demi-écrémé UHT 1L', 'brand' => 'Lactel',
            'description' => 'Lait de vache stérilisé UHT.', 'locale' => 'fr',
            'source' => 'community', 'confidence' => 70,
        ]);
        $french->barcodes()->attach($barcode->getKey());

        $this->getJson('/api/v1/barcode/resolve?code=8690504010012')
            ->assertOk()
            ->assertJsonPath('data.name', 'Yarım yağlı UHT süt 1L');

        $written = GlobalProduct::query()->where('locale', 'en')->sole();
        $this->assertSame('ai_generated', $written->source);
        // Points at the row it was made from, so a bad translation can be traced to its original.
        $this->assertSame((string) $french->getKey(), $written->source_ref);
        // **Linked, or it is unreachable**: the cascade answers through the barcode pivot, so an
        // unlinked row would be rewritten on every scan and found by none of them.
        $this->assertTrue($written->barcodes()->whereKey($barcode->getKey())->exists());
    }

    public function test_a_second_scan_of_a_translated_row_costs_nothing(): void
    {
        // The locale check IS the cache (`ai-design.md` asks for exactly that), so this needs no
        // cache layer to assert: the resolver orders by locale, so once the row exists it wins and
        // the translator is never reached. The fake is scripted with ONE answer, so a second call
        // would fail loudly rather than quietly costing a credit.
        $this->tenant('Alpha');
        config(['ai_gateways.live' => true]);
        AiCreditGrant::create(['kind' => 'plan_allowance', 'credits' => 10,
            'period_start' => Carbon::now()->startOfMonth(), 'expires_at' => Carbon::now()->endOfMonth()]);
        $this->app->instance(ModelCaller::class, new FakeModelCaller([
            ['name' => 'Yarım yağlı UHT süt 1L', 'brand' => 'Lactel', 'description' => 'UHT süt.'],
        ]));

        $barcode = Barcode::forGtin('8690504010012');
        $french = GlobalProduct::create([
            'name' => 'Lait demi-écrémé UHT 1L', 'brand' => 'Lactel', 'locale' => 'fr',
            'source' => 'community', 'confidence' => 70,
        ]);
        $french->barcodes()->attach($barcode->getKey());

        $this->getJson('/api/v1/barcode/resolve?code=8690504010012')->assertOk();
        $this->getJson('/api/v1/barcode/resolve?code=8690504010012')
            ->assertOk()
            ->assertJsonPath('data.name', 'Yarım yağlı UHT süt 1L');

        // One model call, so one usage row, for two scans.
        $this->assertSame(1, AiUsageEvent::query()->count());
    }

    public function test_a_translation_failure_answers_in_the_other_language_rather_than_not_at_all(): void
    {
        // A translation failure costs a LANGUAGE, never an answer. The cascade's whole argument for
        // returning a foreign row is that a product the user can recognise beats none, and that
        // argument does not stop applying because a model was down.
        $this->tenant('Alpha');
        config(['ai_gateways.live' => true]);
        $this->app->instance(ModelCaller::class, new FakeModelCaller([]));

        $barcode = Barcode::forGtin('8690504010012');
        $french = GlobalProduct::create([
            'name' => 'Lait demi-écrémé UHT 1L', 'brand' => 'Lactel', 'locale' => 'fr',
            'source' => 'community', 'confidence' => 70,
        ]);
        $french->barcodes()->attach($barcode->getKey());

        $this->getJson('/api/v1/barcode/resolve?code=8690504010012')
            ->assertOk()
            ->assertJsonPath('data.name', 'Lait demi-écrémé UHT 1L');

        // And nothing half-written was left behind for the next scan to find.
        $this->assertSame(1, GlobalProduct::query()->count());
    }

    public function test_a_row_already_in_the_users_locale_never_reaches_a_model(): void
    {
        // The guard on the cheap path. An empty script means any call at all throws, so this fails
        // loudly if the locale comparison is ever inverted or dropped.
        $this->tenant('Alpha');
        config(['ai_gateways.live' => true]);
        AiCreditGrant::create(['kind' => 'plan_allowance', 'credits' => 10,
            'period_start' => Carbon::now()->startOfMonth(), 'expires_at' => Carbon::now()->endOfMonth()]);
        $this->app->instance(ModelCaller::class, new FakeModelCaller([]));

        $barcode = Barcode::forGtin('8690504010012');
        $english = GlobalProduct::create([
            'name' => 'Semi-skimmed UHT milk 1L', 'brand' => 'Lactel', 'locale' => 'en',
            'source' => 'community', 'confidence' => 70,
        ]);
        $english->barcodes()->attach($barcode->getKey());

        $this->getJson('/api/v1/barcode/resolve?code=8690504010012')
            ->assertOk()
            ->assertJsonPath('data.name', 'Semi-skimmed UHT milk 1L');

        $this->assertSame(0, AiUsageEvent::query()->count());
    }

    public function test_a_case_code_is_never_asked_of_open_food_facts(): void
    {
        // `Gtin::toOpenFoodFacts()` returns null for a 14-significant-digit code: that is a case
        // rather than a consumer item, and OFF does not model it. Asking would be a request that
        // cannot hit.
        $this->tenant('Alpha');

        $this->getJson('/api/v1/barcode/resolve?code=10614141999993')
            ->assertNotFound();

        Http::assertNothingSent();
    }
}
