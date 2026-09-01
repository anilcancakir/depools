<?php

namespace Tests\Feature;

use App\Ai\Contracts\ModelCaller;
use App\Enums\MovementSource;
use App\Models\AiCreditGrant;
use App\Models\Location;
use App\Models\Product;
use App\Models\ProductAlias;
use App\Models\ShelfCandidate;
use App\Models\ShelfRead;
use App\Models\StockMovement;
use App\Models\Team;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Storage;
use Tests\Support\FakeModelCaller;
use Tests\Support\ReceiptImages;
use Tests\TestCase;

/**
 * Reading a photographed shelf into candidates, and letting the accepted ones become stock.
 *
 * Driven through the HTTP endpoints, because the properties worth protecting are about what the
 * CLIENT sees: that a region the model could not name still arrives with its box, that running out
 * of credits is a 200 the screen can explain, and that the accept count is the settled count rather
 * than the region count (D60).
 *
 * **The fixtures are the receipt ones and that is deliberate.** The model is faked, so what the
 * picture shows is read by nothing: what the fixture has to provide is a decodable JPEG. A synthetic
 * "shelf photograph" would be a second drawing routine no assertion could tell from this one.
 */
final class ShelfReadTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();

        Http::preventStrayRequests();
        Storage::fake('local');

        config(['ai_gateways.live' => true]);
    }

    public function test_a_photograph_is_stored_and_a_row_comes_back_to_fill(): void
    {
        $this->tenant();
        $this->model([]);

        $response = $this->postJson('/api/v1/shelf-reads', ['photo' => ReceiptImages::receiptA()])
            ->assertCreated()
            ->assertJsonPath('data.has_document', true)
            ->assertJsonPath('data.confirmed_at', null);

        $shelf = ShelfRead::query()->sole();

        // The row exists BEFORE anything is asked of a model, which is what makes the photograph
        // available to the screen immediately and a failed read resumable rather than an orphan.
        $this->assertNotNull($shelf->document_path);
        $this->assertMatchesRegularExpression('/^[0-9a-f]{32}$/', (string) $shelf->image_phash);
        $this->assertTrue(Storage::disk('local')->exists((string) $shelf->document_path));
        $this->assertSame($shelf->getKey(), $response->json('data.id'));
    }

    public function test_the_same_shelf_photographed_twice_is_two_reads(): void
    {
        $this->tenant();
        $this->model([]);

        $this->postJson('/api/v1/shelf-reads', ['photo' => ReceiptImages::receiptA()])->assertCreated();
        $this->postJson('/api/v1/shelf-reads', ['photo' => ReceiptImages::receiptA()])->assertCreated();

        // **Not deduplicated, unlike a receipt.** The same receipt twice is a mistake; the same shelf
        // twice is a recount, which is how this feature is meant to be used.
        $this->assertSame(2, ShelfRead::query()->count());
    }

    public function test_a_file_that_is_not_an_image_is_refused(): void
    {
        $this->tenant();

        $this->postJson('/api/v1/shelf-reads', [
            'photo' => UploadedFile::fake()->create('notes.pdf', 12, 'application/pdf'),
        ])->assertStatus(422)->assertJsonValidationErrors('photo');
    }

    public function test_the_regions_are_numbered_in_the_order_a_person_scans_a_shelf(): void
    {
        $this->tenant();
        $this->credits(5);

        // Returned bottom-right first, so the numbering cannot be the array's own order.
        $this->model([$this->answer([
            $this->sighting(left: 0.60, top: 0.60, name: 'Zeytinyağı'),
            $this->sighting(left: 0.10, top: 0.10, name: 'Süt'),
            $this->sighting(left: 0.50, top: 0.10, name: 'Ayran'),
        ])]);

        $shelf = $this->upload();

        $response = $this->postJson("/api/v1/shelf-reads/{$shelf}/read")->assertOk();

        // D60: the number is the only thing tying a row to a box, so it starts at one, is contiguous,
        // and reads the way a person scans, top row left to right.
        $this->assertSame([1, 2, 3], $response->json('data.candidates.*.region'));
        $this->assertSame(
            ['Süt', 'Ayran', 'Zeytinyağı'],
            $response->json('data.candidates.*.product_name'),
        );
    }

    public function test_a_region_the_model_could_not_name_still_arrives_with_its_box(): void
    {
        $this->tenant();
        $this->credits(5);
        $this->model([$this->answer([
            $this->sighting(left: 0.10, top: 0.10, name: null),
        ])]);

        $shelf = $this->upload();

        $this->postJson("/api/v1/shelf-reads/{$shelf}/read")
            ->assertOk()
            ->assertJsonPath('data.candidates.0.product_name', null)
            ->assertJsonPath('data.candidates.0.resolution', 'unresolved')
            // `ai-enrichment.md` requires an unnameable region to be PRESENTED rather than invented:
            // the user has to know the app saw something there.
            ->assertJsonPath('data.candidates.0.left', 0.1)
            ->assertJsonPath('data.candidates.0.region', 1);
    }

    public function test_a_box_outside_the_frame_drops_its_whole_entry(): void
    {
        $this->tenant();
        $this->credits(5);
        $this->model([$this->answer([
            $this->sighting(left: 0.10, top: 0.10, name: 'Süt'),
            // Runs off the right edge. The database refuses it either way, and a candidate with no
            // box is unreachable on a screen whose whole design is the link between a row and a
            // rectangle on the photograph.
            $this->sighting(left: 0.90, top: 0.10, width: 0.30, name: 'Yoğurt'),
        ])]);

        $shelf = $this->upload();

        $this->postJson("/api/v1/shelf-reads/{$shelf}/read")
            ->assertOk()
            ->assertJsonCount(1, 'data.candidates')
            ->assertJsonPath('data.candidates.0.product_name', 'Süt');
    }

    public function test_more_regions_than_the_cap_are_cut_at_the_cap(): void
    {
        $this->tenant();
        $this->credits(5);

        $sightings = [];

        for ($i = 0; $i < 20; $i++) {
            $sightings[] = $this->sighting(
                left: ($i % 5) * 0.19,
                top: intdiv($i, 5) * 0.24,
                name: "Ürün {$i}",
            );
        }

        $this->model([$this->answer($sightings)]);

        $shelf = $this->upload();

        // Twelve, and the bound is D60's rather than the model's: twenty numbered boxes are not
        // legible on the 390px screen this is used on. The cap travels in the prompt AND is enforced
        // here, because a prompt is a request.
        $this->postJson("/api/v1/shelf-reads/{$shelf}/read")
            ->assertOk()
            ->assertJsonCount(12, 'data.candidates');
    }

    public function test_a_name_the_tenant_already_stocks_resolves_to_that_product(): void
    {
        $this->tenant();
        $this->credits(5);

        $product = $this->product('Pınar Süt Tam Yağlı 1 lt');

        $this->model([$this->answer([
            $this->sighting(left: 0.10, top: 0.10, name: 'Pınar Süt Tam Yağlı 1 lt'),
        ])]);

        $shelf = $this->upload();

        $this->postJson("/api/v1/shelf-reads/{$shelf}/read")
            ->assertOk()
            ->assertJsonPath('data.candidates.0.resolution', 'matched')
            ->assertJsonPath('data.candidates.0.product_id', $product->getKey());
    }

    public function test_an_alias_answers_before_the_product_name_does(): void
    {
        $this->tenant();
        $this->credits(5);

        $product = $this->product('Pınar Süt Tam Yağlı 1 lt');

        $alias = new ProductAlias;
        $alias->setAttribute('team_id', Team::query()->sole()->getKey());
        $alias->fill([
            'product_id' => $product->getKey(),
            'alias_raw' => 'PNR SUT',
            'alias_normalized' => Product::normaliseName('PNR SUT'),
            'source' => 'scan',
        ]);
        $alias->save();

        $this->model([$this->answer([$this->sighting(left: 0.10, top: 0.10, name: 'PNR SUT')])]);

        $shelf = $this->upload();

        $this->postJson("/api/v1/shelf-reads/{$shelf}/read")->assertOk();

        // The alias table is the first step of the cascade and the cheapest, which is the same order
        // the receipt path uses. `resolved_by` is what says which step answered.
        $this->assertSame('alias', ShelfCandidate::query()->sole()->resolved_by);
    }

    public function test_running_out_of_credits_answers_200_with_the_reason(): void
    {
        $this->tenant();
        // No grant at all: `credits(0)` would violate `ai_credit_grants_credits_are_positive`.
        $caller = $this->model([]);

        $shelf = $this->upload();

        $this->postJson("/api/v1/shelf-reads/{$shelf}/read")
            ->assertOk()
            ->assertJsonCount(0, 'data.candidates')
            ->assertJsonPath('data.last_read_outcome', 'no_credit');

        $this->assertCount(0, $caller->calls, 'no credit means no provider is reached at all');
    }

    public function test_a_photograph_holding_no_stock_is_a_success_not_a_failure(): void
    {
        $this->tenant();
        $this->credits(5);
        $this->model([$this->answer([])]);

        $shelf = $this->upload();

        // A wall is a picture with nothing in it, and the screen draws that differently from a read
        // that failed: one is an honest "nothing here", the other keeps the photograph and offers a
        // retake. A gateway collapsing them would take that choice away.
        $this->postJson("/api/v1/shelf-reads/{$shelf}/read")
            ->assertOk()
            ->assertJsonCount(0, 'data.candidates')
            ->assertJsonPath('data.last_read_outcome', 'succeeded');
    }

    public function test_a_second_read_replaces_the_candidates_and_appends_the_evidence(): void
    {
        $this->tenant();
        $this->credits(5);
        $this->model([
            $this->answer([$this->sighting(left: 0.10, top: 0.10, name: 'Süt')]),
            $this->answer([
                $this->sighting(left: 0.10, top: 0.10, name: 'Süt'),
                $this->sighting(left: 0.50, top: 0.10, name: 'Ayran'),
            ]),
        ]);

        $shelf = $this->upload();

        $this->postJson("/api/v1/shelf-reads/{$shelf}/read")->assertOk()->assertJsonCount(1, 'data.candidates');

        $this->postJson("/api/v1/shelf-reads/{$shelf}/read")
            ->assertOk()
            // Replaced rather than appended: the region numbers are unique per read, and appending
            // would break the only link D60 gives a row to a box.
            ->assertJsonCount(2, 'data.candidates');

        $this->assertSame([1, 2], $this->regions());

        // The evidence accumulates, because `(shelf_read_id, attempt)` is unique and a retry starts
        // its own numbering at 1: without the offset the second pass violates the index.
        $this->assertSame([1, 2], ShelfRead::query()->sole()->extractions->pluck('attempt')->all());
    }

    public function test_the_attempt_row_records_how_many_regions_came_back(): void
    {
        $this->tenant();
        $this->credits(5);
        $this->model([$this->answer([
            $this->sighting(left: 0.10, top: 0.10, name: 'Süt'),
            $this->sighting(left: 0.50, top: 0.10, name: 'Ayran'),
        ])]);

        $shelf = $this->upload();
        $this->postJson("/api/v1/shelf-reads/{$shelf}/read")->assertOk();

        // The whole reason this table exists here and not on the single-product path: nothing has
        // measured what a model returns for a shelf, so the twelve-region cap is a design judgement
        // until these rows say otherwise.
        $extraction = ShelfRead::query()->sole()->extractions->sole();
        $this->assertSame(2, $extraction->regions_found);
        $this->assertSame('succeeded', $extraction->outcome);
    }

    public function test_accepting_a_region_writes_one_movement_and_marks_the_candidate(): void
    {
        $this->tenant();
        $this->credits(5);

        $product = $this->product('Pınar Süt Tam Yağlı 1 lt');
        $location = $this->location();

        $this->model([$this->answer([
            $this->sighting(left: 0.10, top: 0.10, name: 'Pınar Süt Tam Yağlı 1 lt', quantity: '3'),
        ])]);

        $shelf = $this->upload();
        $this->postJson("/api/v1/shelf-reads/{$shelf}/read")->assertOk();

        $this->postJson("/api/v1/shelf-reads/{$shelf}/commit", [
            'location_id' => $location->getKey(),
            'accepted' => ['1' => ['product_id' => $product->getKey(), 'quantity' => 3]],
        ])->assertOk();

        $movement = StockMovement::query()->sole();
        $this->assertSame('3.000', (string) $movement->delta);
        // Everything a camera put into stock says so, which is the audit distinction the ledger
        // exists to keep. Compared against the CASE rather than the string, because the column is
        // cast: asserting on `'photo'` fails against an enum that holds exactly that value.
        $this->assertSame(MovementSource::Photo, $movement->source);
        // D96's granularity: the movement points at the CANDIDATE, so one wrong item out of twelve
        // can be undone alone.
        $this->assertSame(ShelfCandidate::query()->sole()->getKey(), $movement->reference_id);

        $this->assertSame('matched', ShelfCandidate::query()->sole()->resolution);
        $this->assertNotNull(ShelfRead::query()->sole()->confirmed_at);
    }

    public function test_rejecting_a_region_writes_nothing_and_keeps_the_row(): void
    {
        $this->tenant();
        $this->credits(5);

        $location = $this->location();

        $this->model([$this->answer([
            $this->sighting(left: 0.10, top: 0.10, name: 'Fiyat etiketi'),
        ])]);

        $shelf = $this->upload();
        $this->postJson("/api/v1/shelf-reads/{$shelf}/read")->assertOk();

        $this->postJson("/api/v1/shelf-reads/{$shelf}/commit", [
            'location_id' => $location->getKey(),
            'rejected' => [1],
        ])->assertOk();

        // A price label the recogniser took for a product is Tuesday, not an edge case. The row
        // stays visible so it can be un-rejected (D60, on D51's argument).
        $this->assertSame(0, StockMovement::query()->count());
        $this->assertSame('rejected', ShelfCandidate::query()->sole()->resolution);
    }

    public function test_a_half_reviewed_shelf_is_not_confirmed(): void
    {
        $this->tenant();
        $this->credits(5);

        $product = $this->product('Pınar Süt Tam Yağlı 1 lt');
        $location = $this->location();

        $this->model([$this->answer([
            $this->sighting(left: 0.10, top: 0.10, name: 'Pınar Süt Tam Yağlı 1 lt'),
            $this->sighting(left: 0.50, top: 0.10, name: null),
        ])]);

        $shelf = $this->upload();
        $this->postJson("/api/v1/shelf-reads/{$shelf}/read")->assertOk();

        $this->postJson("/api/v1/shelf-reads/{$shelf}/commit", [
            'location_id' => $location->getKey(),
            'accepted' => ['1' => ['product_id' => $product->getKey(), 'quantity' => 1]],
        ])->assertOk();

        // Region 2 is still waiting for a decision, so the read is still in progress however many
        // movements landed. That is also what keeps D94's retention clock from starting early.
        $this->assertNull(ShelfRead::query()->sole()->confirmed_at);
        $this->assertSame(1, StockMovement::query()->count());
    }

    public function test_another_tenants_shelf_read_is_a_404(): void
    {
        $this->tenant('Alpha');
        $this->model([]);
        $shelf = $this->upload();

        $this->tenant('Beta');

        // 404 rather than 403, the same as every other cross-tenant lookup in this API: a refusal
        // that admits the row exists is itself a leak.
        $this->postJson("/api/v1/shelf-reads/{$shelf}/read")->assertNotFound();
        $this->postJson("/api/v1/shelf-reads/{$shelf}/commit", [
            'location_id' => $this->location()->getKey(),
        ])->assertNotFound();
    }

    public function test_the_endpoints_are_behind_authentication(): void
    {
        $this->postJson('/api/v1/shelf-reads', ['photo' => ReceiptImages::receiptA()])
            ->assertUnauthorized();
    }

    /**
     * @return list<int>
     */
    private function regions(): array
    {
        return ShelfCandidate::query()->orderBy('region')->pluck('region')->all();
    }

    /**
     * Uploads a photograph and returns the read's id.
     */
    private function upload(): string
    {
        return (string) $this->postJson('/api/v1/shelf-reads', ['photo' => ReceiptImages::receiptA()])
            ->assertCreated()
            ->json('data.id');
    }

    /**
     * One entry in a scripted answer.
     *
     * @return array<string, mixed>
     */
    private function sighting(
        float $left,
        float $top,
        float $width = 0.15,
        float $height = 0.20,
        ?string $name = 'Süt',
        ?string $quantity = '1',
    ): array {
        return [
            'name' => $name,
            'quantity' => $quantity,
            'unit' => null,
            'left' => $left,
            'top' => $top,
            'width' => $width,
            'height' => $height,
            'confidence' => 80,
        ];
    }

    /**
     * A scripted model answer.
     *
     * @param  list<array<string, mixed>>  $sightings
     * @return array<string, mixed>
     */
    private function answer(array $sightings): array
    {
        return ['products' => $sightings];
    }

    /**
     * @param  list<array<string, mixed>>  $script
     */
    private function model(array $script): FakeModelCaller
    {
        $caller = new FakeModelCaller($script);

        $this->app->instance(ModelCaller::class, $caller);

        return $caller;
    }

    private function product(string $name): Product
    {
        return Product::create(['name' => $name, 'base_unit' => 'C62']);
    }

    private function location(): Location
    {
        return Location::create(['name' => 'Depo '.uniqid()]);
    }

    private function tenant(string $name = 'Alpha'): void
    {
        /** @var User $user */
        $user = User::factory()->createOne();
        $team = Team::create(['name' => $name, 'user_id' => $user->getKey()]);
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
