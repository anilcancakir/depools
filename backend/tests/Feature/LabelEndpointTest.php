<?php

namespace Tests\Feature;

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

        $pdf = $this->postJson('/api/v1/labels/pdf', [
            'template' => 'a4_8_up_105x70',
            'fields' => ['name', 'code'],
            'items' => [['product_id' => $product->getKey()]],
        ])->assertOk()->getContent();

        $text = $this->extract($pdf);

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

        $pdf = $this->postJson('/api/v1/labels/pdf', [
            'template' => 'a4_8_up_105x70',
            'fields' => ['name', 'code'],
            'items' => [['product_id' => $product->getKey()]],
        ])->assertOk()->getContent();

        $text = $this->extract($pdf);

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
        $pdf = $this->postJson('/api/v1/labels/pdf', [
            'template' => 'a4_24_up_70x37',
            'fields' => ['name'],
            'items' => [['product_id' => $product->getKey(), 'copies' => 25]],
        ])->assertOk()->getContent();

        $path = $this->write($pdf);

        $info = new Process(['pdfinfo', $path]);
        $info->run();

        $this->assertStringContainsString('Pages:           2', $info->getOutput());

        unlink($path);
    }

    public function test_the_preview_is_a_png_and_is_served_from_the_cache_the_second_time(): void
    {
        $this->tenant();
        $this->requireRenderToolchain();

        Storage::fake('local');

        $product = $this->product('Şeker (Toz) 1 kg');

        $payload = [
            'template' => 'a4_24_up_70x37',
            'fields' => ['name', 'code'],
            'items' => [['product_id' => $product->getKey()]],
        ];

        $first = $this->postJson('/api/v1/labels/preview', $payload)->assertOk();
        $this->assertSame('image/png', $first->headers->get('Content-Type'));

        $cached = Storage::disk('local')->files('label-previews');
        $this->assertCount(1, $cached);

        // The same request again must not render a second file: that is what makes a preview
        // affordable while the user flips through templates (D71).
        $this->postJson('/api/v1/labels/preview', $payload)->assertOk();

        $this->assertSame($cached, Storage::disk('local')->files('label-previews'));
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
