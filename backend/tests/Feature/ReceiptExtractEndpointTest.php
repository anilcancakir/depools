<?php

namespace Tests\Feature;

use App\Ai\Contracts\ModelCaller;
use App\Models\AiCreditGrant;
use App\Models\Product;
use App\Models\ProductAlias;
use App\Models\Receipt;
use App\Models\ReceiptLine;
use App\Models\Scopes\TeamScope;
use App\Models\Team;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Storage;
use Tests\Support\FakeModelCaller;
use Tests\TestCase;

/**
 * `POST api/v1/receipts/{receipt}/extract`: reading a stored photograph into lines.
 *
 * Slice 1 stored the document and stopped. This is where a receipt stops being a picture with a row
 * beside it and becomes something the review screen can work through.
 */
final class ReceiptExtractEndpointTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();

        Http::preventStrayRequests();
        config(['ai_gateways.live' => true]);
        Storage::fake(config('media.documents.disk'));
    }

    public function test_another_tenants_receipt_is_a_404_rather_than_a_403(): void
    {
        // Written before the feature, as `.claude/rules/backend.md` requires. 404 and not 403: the
        // route resolves through `TeamScope`, so a receipt belonging to somebody else does not
        // exist as far as this request is concerned, and a 403 would confirm that it does.
        $this->tenant();
        $foreign = $this->foreignReceipt();
        $this->credits(5);
        $this->model([$this->answer()]);

        $this->postJson("/api/v1/receipts/{$foreign->getKey()}/extract")->assertNotFound();

        $this->assertSame(0, ReceiptLine::query()->withoutGlobalScope(TeamScope::class)->count());
    }

    public function test_it_writes_the_lines_and_answers_with_them(): void
    {
        $this->tenant();
        $this->credits(5);
        $this->model([$this->answer()]);
        $receipt = $this->receipt();

        $response = $this->postJson("/api/v1/receipts/{$receipt->getKey()}/extract");

        $response->assertOk()
            ->assertJsonPath('data.lines.0.raw_name', 'PNR SUT 1LT')
            ->assertJsonPath('data.lines.1.raw_name', 'ORG KEM TAV')
            ->assertJsonCount(2, 'data.lines');

        $this->assertSame(2, $receipt->lines()->count());
        $this->assertSame([1, 2], $receipt->lines()->pluck('line_number')->all());
    }

    public function test_the_header_the_model_read_lands_on_the_receipt(): void
    {
        $this->tenant();
        $this->credits(5);
        $this->model([$this->answer()]);
        $receipt = $this->receipt();

        $this->postJson("/api/v1/receipts/{$receipt->getKey()}/extract")->assertOk();

        $receipt->refresh();

        $this->assertSame('MIGROS TICARET A.S.', $receipt->supplier_name);
        $this->assertSame('154.75', $receipt->total_amount);
        $this->assertSame('TRY', $receipt->currency);
        $this->assertSame('2026-08-30', $receipt->issued_on?->toDateString());
        $this->assertSame('extracted', $receipt->status);
    }

    public function test_every_attempt_lands_in_receipt_extractions(): void
    {
        // D95's table, filled. The first entry answers with no lines, which the gateway rejects, so
        // the second is asked: two rows, and the failed one keeps its raw payload because that is
        // the row O2's bake-off wants to read.
        $this->tenant();
        $this->credits(5);
        $this->model([['lines' => []], $this->answer()]);
        $receipt = $this->receipt();

        $this->postJson("/api/v1/receipts/{$receipt->getKey()}/extract")->assertOk();

        $attempts = $receipt->extractions()->get();

        $this->assertCount(2, $attempts);
        $this->assertSame([1, 2], $attempts->pluck('attempt')->all());
        $this->assertSame(['schema_invalid', 'succeeded'], $attempts->pluck('outcome')->all());
        $this->assertSame(['lines' => []], $attempts[0]->raw_payload);
        $this->assertSame(0, $attempts[0]->lines_found);
        $this->assertSame(2, $attempts[1]->lines_found);
    }

    public function test_with_no_credits_the_receipt_survives_and_the_manual_path_stays_open(): void
    {
        // `receipt-ingestion.md`: extraction is what stops, not the feature. So this is a 200 with
        // no lines rather than an error, and the declined attempt is still recorded, because "this
        // tenant is hitting their limit" is the most actionable fact there is.
        $this->tenant();
        $this->model([$this->answer()]);
        $receipt = $this->receipt();

        $this->postJson("/api/v1/receipts/{$receipt->getKey()}/extract")
            ->assertOk()
            ->assertJsonCount(0, 'data.lines');

        $receipt->refresh();

        $this->assertSame('pending', $receipt->status, 'nothing was read, so nothing was extracted');
        $this->assertSame('no_credit', $receipt->extractions()->sole()->outcome);
    }

    public function test_a_receipt_whose_document_is_gone_is_refused(): void
    {
        $this->tenant();
        $this->credits(5);
        $caller = $this->model([$this->answer()]);
        $receipt = $this->receipt();
        $receipt->forceFill(['document_deleted_at' => Carbon::now()])->save();

        $this->postJson("/api/v1/receipts/{$receipt->getKey()}/extract")->assertStatus(422);

        $this->assertSame([], $caller->calls, 'no picture, no call, no credit spent');
    }

    public function test_a_receipt_that_already_has_lines_is_not_read_again(): void
    {
        // Per-line state is what makes an interrupted confirmation resumable, so a second extraction
        // over lines the user has been working through would delete their work. 409 and the receipt
        // as it stands, which is the same answer `store` gives a duplicate upload.
        $this->tenant();
        $this->credits(5);
        $this->model([$this->answer(), $this->answer()]);
        $receipt = $this->receipt();

        $this->postJson("/api/v1/receipts/{$receipt->getKey()}/extract")->assertOk();
        $this->postJson("/api/v1/receipts/{$receipt->getKey()}/extract")->assertStatus(409);

        $this->assertSame(2, $receipt->lines()->count(), 'the first read stands');
        $this->assertSame(1, $receipt->extractions()->count(), 'and the second never reached a model');
    }

    public function test_a_line_matching_one_of_the_tenants_own_products_is_resolved(): void
    {
        $this->tenant();
        $this->credits(5);
        $this->model([$this->answer()]);
        // The till's own string, as a product name. A tenant who typed it that way is the easy half
        // of the cascade's first step; the abbreviation nobody has confirmed is the other line.
        $product = Product::create(['name' => 'PNR SUT 1LT']);
        $receipt = $this->receipt();

        $this->postJson("/api/v1/receipts/{$receipt->getKey()}/extract")->assertOk();

        $lines = $receipt->lines()->get();

        $this->assertSame((string) $product->getKey(), $lines[0]->product_id);
        $this->assertSame('matched', $lines[0]->resolution);
        $this->assertSame('own_product', $lines[0]->resolved_by);

        $this->assertNull($lines[1]->product_id);
        $this->assertSame('unresolved', $lines[1]->resolution, 'and this one is what the user is asked about');
    }

    public function test_a_confirmed_alias_answers_before_a_product_name_does(): void
    {
        // The compounding half. `ai-design.md`: every resolution the user confirms strengthens step
        // one for next time, and an abbreviation the till prints will never match a name a person
        // typed. So the alias wins even where a product name would also have matched.
        $this->tenant();
        $this->credits(5);
        $this->model([$this->answer()]);

        $byName = Product::create(['name' => 'PNR SUT 1LT']);
        $byAlias = Product::create(['name' => 'Pınar Süt Tam Yağlı 1 lt']);

        $alias = new ProductAlias;
        $alias->fill([
            'product_id' => $byAlias->getKey(),
            'alias_normalized' => Product::normaliseName('PNR SUT 1LT'),
            'alias_raw' => 'PNR SUT 1LT',
            'source' => 'receipt',
        ]);
        $alias->setAttribute('team_id', $this->teamId);
        $alias->save();

        $receipt = $this->receipt();

        $this->postJson("/api/v1/receipts/{$receipt->getKey()}/extract")->assertOk();

        $line = $receipt->lines()->where('line_number', 1)->sole();

        $this->assertSame((string) $byAlias->getKey(), $line->product_id);
        $this->assertSame('alias', $line->resolved_by);
        $this->assertNotSame((string) $byName->getKey(), $line->product_id);
    }

    public function test_a_name_two_products_share_is_left_to_the_user(): void
    {
        // `products.name_normalized` carries a trigram index and no uniqueness (only `(team_id, sku)`
        // is unique), so two rows can fold to one name. Picking either would be a guess presented as
        // a match, and mandatory per-line confirmation exists precisely so the app does not do that.
        //
        // The two names differ only in CASE. An earlier version of this test used a doubled space
        // and passed for the wrong reason: measured, `Product::normaliseName` lowercases and trims
        // but does NOT collapse inner whitespace, so `pnr  sut 1lt` folds to a different string and
        // the two rows never collided at all.
        $this->tenant();
        $this->credits(5);
        $this->model([$this->answer()]);
        Product::create(['name' => 'PNR SUT 1LT']);
        Product::create(['name' => 'pnr sut 1lt']);
        $receipt = $this->receipt();

        $this->postJson("/api/v1/receipts/{$receipt->getKey()}/extract")->assertOk();

        $line = $receipt->lines()->where('line_number', 1)->sole();

        $this->assertSame('unresolved', $line->resolution);
        $this->assertNull($line->product_id);
    }

    private function receipt(): Receipt
    {
        $path = config('media.documents.directory').'/fixture.jpg';

        Storage::disk(config('media.documents.disk'))->put($path, $this->jpeg());

        $receipt = new Receipt;
        $receipt->fill([
            'kind' => 'fis',
            'status' => 'pending',
            'document_path' => $path,
            'image_phash' => str_repeat('a', 32),
        ]);
        $receipt->setAttribute('team_id', $this->teamId);
        $receipt->save();

        return $receipt;
    }

    /**
     * A receipt belonging to somebody else entirely.
     */
    private function foreignReceipt(): Receipt
    {
        /** @var User $other */
        $other = User::factory()->createOne();
        $team = Team::create(['name' => 'Beta', 'user_id' => $other->getKey()]);

        $receipt = new Receipt;
        $receipt->fill([
            'kind' => 'fis',
            'status' => 'pending',
            'document_path' => config('media.documents.directory').'/foreign.jpg',
            'image_phash' => str_repeat('b', 32),
        ]);
        // `save()`, not `saveQuietly()`: the UUIDv7 key is minted in a `creating` hook, so a quiet
        // save lands a null `id` on a NOT NULL column. `BelongsToTeam`'s hook only fills `team_id`
        // when it is null, so the explicit stamp above still wins.
        $receipt->setAttribute('team_id', $team->getKey());
        $receipt->save();

        return $receipt;
    }

    /**
     * The smallest real JPEG the encoder will accept, so the downscale has something to read.
     */
    private function jpeg(): string
    {
        $image = imagecreatetruecolor(40, 60);
        ob_start();
        imagejpeg($image);
        $bytes = (string) ob_get_clean();
        imagedestroy($image);

        return $bytes;
    }

    private function model(array $script): FakeModelCaller
    {
        $caller = new FakeModelCaller($script);

        $this->app->instance(ModelCaller::class, $caller);

        return $caller;
    }

    private function answer(): array
    {
        return [
            'supplier_name' => 'MIGROS TICARET A.S.',
            'supplier_tax_id' => '6220084383',
            'invoice_number' => 'FIS-0042',
            'issued_on' => '2026-08-30',
            'total_amount' => '154.75',
            'currency' => 'TRY',
            'lines' => [
                [
                    'raw_name' => 'PNR SUT 1LT',
                    'quantity' => '2',
                    'raw_unit_code' => 'AD',
                    'unit_price' => '32.50',
                    'line_total' => '65.00',
                    'vat_rate' => '1',
                    'confidence' => 92,
                ],
                [
                    'raw_name' => 'ORG KEM TAV',
                    'quantity' => '1.240',
                    'raw_unit_code' => 'KG',
                    'unit_price' => '72.38',
                    'line_total' => '89.75',
                    'vat_rate' => '1',
                    'confidence' => 71,
                ],
            ],
        ];
    }

    private string $teamId;

    private function tenant(): void
    {
        /** @var User $user */
        $user = User::factory()->createOne();
        $team = Team::create(['name' => 'Alpha', 'user_id' => $user->getKey()]);
        $user->forceFill(['current_team_id' => $team->getKey()])->save();
        $user->refresh();

        $this->actingAs($user, 'sanctum');
        $this->teamId = (string) $team->getKey();
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
