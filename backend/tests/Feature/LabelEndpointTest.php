<?php

namespace Tests\Feature;

use App\Labels\LabelSheetBuilder;
use App\Labels\LabelSheetRenderer;
use App\Labels\SheetTemplate;
use App\Models\Barcode;
use App\Models\Product;
use App\Models\Team;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Storage;
use Symfony\Component\Process\Process;
use Tests\Concerns\NeedsRenderToolchain;
use Tests\TestCase;

/**
 * The three label endpoints, over real HTTP.
 *
 * The tenancy test is first and it is written the way `backend.md` requires: a product id belonging to
 * another team reaches a scoped query and is simply not found, so the answer is 404 rather than 403.
 * That matters more here than on a read endpoint, because the response is a FILE: a leak would be a
 * printable sheet of another tenant's product names.
 */
final class LabelEndpointTest extends TestCase
{
    use NeedsRenderToolchain;
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();

        // **Every test gets an empty render cache**, because several read `files('label-sheets')[0]`
        // and a shared disk would let one test's PDF answer another's assertion. It also stops the
        // suite leaving rendered sheets in `storage/`.
        Storage::fake('local');
    }

    public function test_a_product_from_another_team_is_not_found_rather_than_refused(): void
    {
        $alpha = $this->tenant('Alpha');
        $mine = $this->product('Pınar Süt Tam Yağlı 1 lt');

        // A second tenant with its own product, then back to the first ONE rather than to a third team
        // that happens to share its name.
        $this->tenant('Beta');
        $theirs = $this->product('Someone Else Milk');

        $this->actingAs($alpha, 'sanctum');

        $this->postJson('/api/v1/labels/pdf', [
            'template' => 'a4_24_up_70x37',
            'items' => [['product_id' => $theirs->getKey()]],
        ])->assertNotFound();

        // And the same request for its own product is not refused, so the 404 above is about tenancy
        // rather than about the endpoint being broken.
        $this->requireRenderToolchain();

        $this->postJson('/api/v1/labels/pdf', [
            'template' => 'a4_24_up_70x37',
            'items' => [['product_id' => $mine->getKey()]],
        ])->assertOk();
    }

    public function test_the_endpoints_are_behind_authentication(): void
    {
        $this->getJson('/api/v1/labels/templates')->assertUnauthorized();
        $this->postJson('/api/v1/labels/pdf', [])->assertUnauthorized();
        $this->postJson('/api/v1/labels/preview', [])->assertUnauthorized();
    }

    public function test_the_catalogue_carries_the_geometry_and_the_code_ceiling(): void
    {
        $this->tenant();

        $response = $this->getJson('/api/v1/labels/templates')->assertOk();

        $keys = array_column($response->json('data'), 'key');
        $this->assertContains('a4_65_up_38x21', $keys);

        $smallest = collect($response->json('data'))->firstWhere('key', 'a4_65_up_38x21');

        $this->assertSame(65, $smallest['per_sheet']);
        // Loose, because a whole float crosses JSON as an int: the API sends `38`, not `38.0`.
        $this->assertEqualsWithDelta(38, $smallest['label_width_mm'], 0.001);

        // **The number that makes "this field does not fit" a fact rather than a heuristic.** A
        // Code 128 set B symbol is 11(n+2)+13 modules plus 20 of quiet zone, and GS1's absolute floor
        // is a 0.250 mm module, so 35 mm of usable width holds seven characters. The client currently
        // guesses the same thing from the label's height being under 30 mm.
        $this->assertSame(7, $smallest['max_code_length']);

        $largest = collect($response->json('data'))->firstWhere('key', 'a4_8_up_105x70');
        $this->assertSame(32, $largest['max_code_length']);
    }

    public function test_an_unknown_template_is_refused_rather_than_swapped_for_a_default(): void
    {
        $this->tenant();
        $product = $this->product('Şeker (Toz) 1 kg');

        // Printing a different layout than the one asked for is a page of stickers that miss their
        // die-cut, so the vocabulary is closed at the boundary.
        $this->postJson('/api/v1/labels/pdf', [
            'template' => 'a4_9999_up',
            'items' => [['product_id' => $product->getKey()]],
        ])->assertUnprocessable()->assertJsonValidationErrors('template');
    }

    public function test_a_products_own_gtin_is_printed_rather_than_a_generated_code(): void
    {
        $this->tenant();
        $this->requireRenderToolchain();

        $product = $this->product('Pınar Süt Tam Yağlı 1 lt');

        // Stored zero-padded to 14, which is `barcodes`' own identity rule (D85).
        $barcode = Barcode::create(['gtin' => str_pad('8690504004073', 14, '0', STR_PAD_LEFT)]);

        // Through the model method rather than a raw `attach`, which `backend.md` requires: a pivot row
        // is a row in a tenant table and nothing stamps `team_id` on it automatically.
        $product->linkBarcode($barcode);

        $this->postJson('/api/v1/labels/pdf', [
            'template' => 'a4_8_up_105x70',
            'fields' => ['name', 'code'],
            'items' => [['product_id' => $product->getKey()]],
        ])->assertOk();

        $text = $this->lastRenderedPdf();

        // **The significant digits, not the padding.** A GTIN row carries no `code` column at all, so
        // reading `code` alone would have generated an internal code for a product that has a real
        // barcode; and printing the stored form would put `00008690504004073` on the label.
        $this->assertStringContainsString('8690504004073', $text);
        $this->assertStringNotContainsString('00008690504004073', $text);
    }

    public function test_a_product_with_no_barcode_gets_one_rather_than_being_refused(): void
    {
        $this->tenant();
        $this->requireRenderToolchain();

        $product = $this->product('Kablo bağı 200 mm');

        $this->postJson('/api/v1/labels/pdf', [
            'template' => 'a4_8_up_105x70',
            'fields' => ['name', 'code'],
            'items' => [['product_id' => $product->getKey()]],
        ])->assertOk();

        $text = $this->lastRenderedPdf();

        // Criterion 6: an internal code cannot be confused with a manufacturer EAN-13, and letters are
        // what guarantee that rather than the prefix being recognisable.
        $this->assertMatchesRegularExpression('/DPL[0-9A-F]{4}/', $text);
    }

    public function test_copies_become_that_many_stickers(): void
    {
        $this->tenant();
        $this->requireRenderToolchain();

        $product = $this->product('Tornavida Seti PH2');

        // 25 copies on a 24-cell sheet: the boundary that decides whether the 25th sticker prints.
        $this->postJson('/api/v1/labels/pdf', [
            'template' => 'a4_24_up_70x37',
            'fields' => ['name'],
            'items' => [['product_id' => $product->getKey(), 'copies' => 25]],
        ])->assertOk();

        $path = $this->write(Storage::disk('local')->get(Storage::disk('local')->files('label-sheets')[0]));

        $info = new Process(['pdfinfo', $path]);
        $info->run();

        $this->assertStringContainsString('Pages:           2', $info->getOutput());

        unlink($path);
    }

    public function test_the_preview_is_a_png_and_is_served_from_the_cache_the_second_time(): void
    {
        $this->tenant();
        $this->requireRenderToolchain();

        $product = $this->product('Şeker (Toz) 1 kg');

        $payload = [
            'template' => 'a4_24_up_70x37',
            'fields' => ['name', 'code'],
            'items' => [['product_id' => $product->getKey()]],
        ];

        $first = $this->postJson('/api/v1/labels/preview', $payload)->assertOk();

        // A url rather than the bytes: `Image.network` cannot carry a bearer token and magic's `Http`
        // facade has no binary response mode, so a streamed PNG is a shape the app cannot use.
        //
        // **The signature is deliberately NOT asserted here.** `Storage::fake` mints an unsigned url
        // (measured: `?expiration=...` with no `signature=`), so the assertion would be about the fake
        // rather than about the code. Signing is `MediaUrl`'s own concern, with its own measured trap
        // recorded there: `temporaryUrl`, never `temporarySignedRoute`.
        $this->assertStringContainsString('label-previews/', $first->json('data.url'));
        $this->assertStringContainsString('expiration=', $first->json('data.url'));
        $this->assertNotNull($first->json('data.expires_at'));

        $cached = Storage::disk('local')->files('label-previews');
        $this->assertCount(1, $cached);

        // The same request again must not render a second file: that is what makes a preview
        // affordable while the user flips through templates (D71).
        $this->postJson('/api/v1/labels/preview', $payload)->assertOk();

        $this->assertSame($cached, Storage::disk('local')->files('label-previews'));
    }

    public function test_the_preview_is_the_whole_sheet_and_not_a_viewport_crop(): void
    {
        $this->tenant();
        $this->requireRenderToolchain();

        $product = $this->product('Kablo bağı 200 mm');

        $this->postJson('/api/v1/labels/preview', [
            'template' => 'a4_65_up_38x21',
            'fields' => ['name'],
            'items' => [['product_id' => $product->getKey(), 'copies' => 50]],
        ])->assertOk();

        $file = Storage::disk('local')->files('label-previews')[0];
        [$width, $height] = getimagesizefromstring(Storage::disk('local')->get($file));

        // **`paperSize` is a PDF option and never reaches a screenshot.** Browsershot's constructor
        // sets `windowSize(800, 600)` unconditionally and puppeteer defaults to `fullPage: false`, so
        // without `fullPage()` this was an 800x600 crop of a 1122.5 px sheet: cells 1 to 35 of 65,
        // measured. A4 at 96 dpi is 794x1123, and the assertion is on the HEIGHT because that is the
        // axis the crop took.
        $this->assertGreaterThanOrEqual(1100, $height, 'The preview is a viewport crop, not the sheet.');
        $this->assertGreaterThanOrEqual(780, $width);
    }

    public function test_a_gtin_wins_over_an_internal_code_whichever_row_the_plan_returns(): void
    {
        $this->tenant();
        $this->requireRenderToolchain();

        $product = $this->product('Pınar Süt Tam Yağlı 1 lt');

        // **Both regimes on one product, which is reachable**: `BarcodeLinker` writes a `gtin` row for
        // anything that could be a GTIN and a `(code, symbology)` row otherwise, and `linkBarcode`
        // uses `syncWithoutDetaching`, which adds. The Code 128 row is attached FIRST so an unordered
        // `first()` is likely to return it, which is what used to print an internal code for a product
        // carrying a real manufacturer barcode.
        $product->linkBarcode(Barcode::forCode('SHELF-LABEL-1', 'code128'));
        $product->linkBarcode(Barcode::forGtin('8690504004073'));

        $this->postJson('/api/v1/labels/pdf', [
            'template' => 'a4_8_up_105x70',
            'fields' => ['name', 'code'],
            'items' => [['product_id' => $product->getKey()]],
        ])->assertOk();

        $text = $this->lastRenderedPdf();

        $this->assertStringContainsString('8690504004073', $text);
        $this->assertStringNotContainsString('SHELF-LABEL-1', $text);
    }

    public function test_a_code_too_long_for_the_label_is_refused_by_name(): void
    {
        $this->tenant();

        $product = $this->product('Pınar Süt Tam Yağlı 1 lt');
        $product->linkBarcode(Barcode::forGtin('8690504004073'));

        // 13 digits is 198 drawn modules, which needs 49.5 mm at GS1's floor against the 35 mm this
        // label offers. `unscannableCodes()` computed exactly this and was called by nothing, so the
        // sheet rendered at 0.177 mm per module: perfect on screen, unreadable on paper.
        $this->postJson('/api/v1/labels/pdf', [
            'template' => 'a4_65_up_38x21',
            'fields' => ['name', 'code'],
            'items' => [['product_id' => $product->getKey()]],
        ])->assertUnprocessable()->assertJsonValidationErrors('template');

        // And the same code on a label with room is not refused, so the 422 is about millimetres.
        $this->requireRenderToolchain();

        $this->postJson('/api/v1/labels/pdf', [
            'template' => 'a4_8_up_105x70',
            'fields' => ['name', 'code'],
            'items' => [['product_id' => $product->getKey()]],
        ])->assertOk();
    }

    public function test_a_code_outside_code_128_is_a_refusal_rather_than_a_500(): void
    {
        $this->tenant();

        $product = $this->product('Yoğurt 2 kg');

        // `Barcode::forCode` only trims, so a Turkish internal code is storable. Encoding it would
        // silently produce a barcode that scans as other characters, so the encoder throws; without
        // the controller catching that, the user asking for a label got a stack trace.
        $product->linkBarcode(Barcode::forCode('YOĞURT-1', 'code128'));

        $this->postJson('/api/v1/labels/pdf', [
            'template' => 'a4_8_up_105x70',
            'fields' => ['name', 'code'],
            'items' => [['product_id' => $product->getKey()]],
        ])->assertUnprocessable()->assertJsonValidationErrors('items');
    }

    public function test_the_generated_code_is_wide_enough_not_to_collide(): void
    {
        $this->tenant();

        $builder = app(LabelSheetBuilder::class);

        $codes = [];

        for ($i = 0; $i < 40; $i++) {
            $codes[] = $builder->codeFor($this->product('Product '.$i));
        }

        // **Four hex characters reached a 50% birthday collision at 301 products in one team**, and the
        // comment defending it said "the id is already unique", which is true of the id and not of its
        // last 16 bits. Eight moves the crossing past 77,000. Forty samples cannot prove a collision
        // rate; what it pins is the WIDTH, which is the thing that was wrong.
        foreach ($codes as $code) {
            $this->assertMatchesRegularExpression('/^DPL[0-9A-F]{8}$/', $code);
        }

        $this->assertSame(count($codes), count(array_unique($codes)));
    }

    public function test_the_preview_cache_is_scoped_to_the_team(): void
    {
        $alpha = $this->tenant('Alpha');
        $renderer = app(LabelSheetRenderer::class);
        $builder = app(LabelSheetBuilder::class);
        $template = SheetTemplate::fromKey('a4_24_up_70x37');

        $mine = $this->product('Whole Milk 1 L');
        [$alphaSheet] = $builder->build([['product_id' => $mine->getKey()]], ['name'], 'Same Name', 'team-a');
        [$betaSheet] = $builder->build([['product_id' => $mine->getKey()]], ['name'], 'Same Name', 'team-b');

        // Defence in depth rather than a live leak: the cached PNG is a pure function of the key, so a
        // collision would serve an image identical to what the requester would have rendered anyway.
        // But the isolation of a file holding product names should rest on `team_id` rather than on a
        // 128-bit non-cryptographic hash, and one string in the signature is what that costs.
        $this->assertNotSame(
            $renderer->cacheKey($template, $alphaSheet),
            $renderer->cacheKey($template, $betaSheet),
        );

        $this->assertNotNull($alpha->currentTeam);
    }

    public function test_an_uppercase_product_id_is_not_a_tenancy_answer_to_a_formatting_question(): void
    {
        $this->tenant();
        $this->requireRenderToolchain();

        $product = $this->product('Şeker (Toz) 1 kg');

        // PostgreSQL renders `uuid` lower-case, so an uppercase id matched `whereIn` (the database
        // compares uuids, not strings) and then missed the keyed collection, which turned a formatting
        // difference into a 404 that reads like an isolation failure. It renders now, and the point of
        // the assertion is the ABSENCE of that 404 rather than the 200.
        $this->postJson('/api/v1/labels/pdf', [
            'template' => 'a4_8_up_105x70',
            'fields' => ['name'],
            'items' => [['product_id' => strtoupper((string) $product->getKey())]],
        ])->assertOk();
    }

    /**
     * The text of the PDF the last render wrote.
     *
     * The endpoints answer with a signed url now, and the file behind it is on the cache disk. Reading
     * the disk rather than parsing the url keeps the test independent of how the url is shaped, which
     * is `MediaUrl`'s business and has its own measured traps.
     */
    private function lastRenderedPdf(): string
    {
        $files = Storage::disk('local')->files('label-sheets');

        $this->assertNotEmpty($files, 'The render wrote no PDF to the cache disk.');

        return $this->extract(Storage::disk('local')->get($files[0]));
    }

    private function extract(string $pdf): string
    {
        $path = $this->write($pdf);

        $process = new Process(['pdftotext', '-layout', $path, '-']);
        $process->run();

        unlink($path);

        return $process->getOutput();
    }

    private function write(string $pdf): string
    {
        $path = tempnam(sys_get_temp_dir(), 'label').'.pdf';
        file_put_contents($path, $pdf);

        return $path;
    }

    /**
     * A fresh tenant, authenticated, RETURNED so a test can switch back to it.
     *
     * **Returning the user is what makes a tenancy test honest here.** Calling this twice with the same
     * name creates two teams, so "switching back" by calling it again is a third tenant and every one
     * of its own products is a 404: the assertion passes for the wrong reason and the test proves
     * nothing about isolation. `ShelfReadTest`'s version returns void because nothing there needs to
     * come back.
     */
    private function tenant(string $name = 'Alpha'): User
    {
        /** @var User $user */
        $user = User::factory()->createOne();
        $team = Team::create(['name' => $name, 'user_id' => $user->getKey()]);
        $user->forceFill(['current_team_id' => $team->getKey()])->save();
        $user->refresh();

        $this->actingAs($user, 'sanctum');

        return $user;
    }

    private function product(string $name): Product
    {
        // The same shape `ShelfReadTest` uses: under an auth context `BelongsToTeam` stamps `team_id`
        // on create, which is why no test ever passes one.
        return Product::create(['name' => $name, 'base_unit' => 'C62']);
    }
}
