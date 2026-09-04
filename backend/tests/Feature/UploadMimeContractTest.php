<?php

namespace Tests\Feature;

use App\Ai\Contracts\ModelCaller;
use App\Models\Location;
use App\Models\Product;
use App\Models\Team;
use App\Models\User;
use Closure;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Storage;
use Illuminate\Testing\TestResponse;
use Tests\Support\FakeModelCaller;
use Tests\TestCase;

/**
 * What each upload endpoint accepts, one test per endpoint, deliberately not one test for all five.
 *
 * Five endpoints take a file and they answer to THREE different format lists. Three of them DECODE
 * the bytes on the server (`media.documents` for a receipt and a shelf photograph, `media.enrichment`
 * for a product photograph), so their list is what GD can read; two only STORE the bytes for a client
 * to render later (`media.images`), so their list is what a browser can display. `webp` is the format
 * that sits in the gap, and `config/media.php` carries the argument beside the block it belongs to.
 *
 * **Nothing else in the suite can tell those three lists apart.** Widening a decoding path to the
 * rendering list passes every other test in this repository, and the failure it produces is a 500 out
 * of `imagecreatefromstring` on a box whose GD was built without WebP. So each test below states the
 * list ITS endpoint accepts, and a future merge of two request classes fails here rather than
 * silently changing which files a decoding path admits.
 *
 * The second half of each test pins the SOURCE rather than the values: it narrows one config block
 * and asserts that exactly one endpoint moved. Today `documents` and `enrichment` happen to hold the
 * same three formats, so a merge of those two would be invisible to a value assertion alone.
 */
final class UploadMimeContractTest extends TestCase
{
    use RefreshDatabase;

    /**
     * The three blocks an upload rule can read its format list from.
     *
     * @var list<string>
     */
    private const BLOCKS = ['media.images', 'media.documents', 'media.enrichment'];

    protected function setUp(): void
    {
        parent::setUp();

        // Beside `AI_LIVE=false` in phpunit.xml: a mistake reaching a provider becomes a failure
        // naming the URL rather than a live call.
        Http::preventStrayRequests();

        Storage::fake((string) config('media.documents.disk'));
        Storage::fake((string) config('media.enrichment.disk'));
        Storage::fake((string) config('media.images.disk'));

        /** @var User $user */
        $user = User::factory()->createOne(['locale' => 'en']);
        $team = Team::create(['name' => 'Alpha', 'user_id' => $user->getKey()]);
        $user->forceFill(['current_team_id' => $team->getKey()])->save();

        $this->actingAs($user->refresh(), 'sanctum');

        // No credits are granted anywhere in this file, so the read answers 200 with no card and the
        // model is never reached. The fake is bound so that a path which DID reach one fails loudly.
        $this->app->instance(ModelCaller::class, new FakeModelCaller([]));
    }

    public function test_a_product_photograph_accepts_only_the_formats_the_server_can_decode(): void
    {
        $upload = fn (UploadedFile $file): TestResponse => $this->postJson(
            '/api/v1/products/recognise',
            ['photo' => $file],
        );

        $this->assertFormats($upload, 'photo', accepts: ['jpg', 'png'], refuses: ['webp', 'gif']);
        $this->assertFormatsComeFrom('media.enrichment', $upload, 'photo');
    }

    public function test_a_receipt_upload_accepts_only_the_formats_the_server_can_decode(): void
    {
        $upload = fn (UploadedFile $file): TestResponse => $this->postJson(
            '/api/v1/receipts',
            ['image' => $file],
        );

        $this->assertFormats($upload, 'image', accepts: ['jpg', 'png'], refuses: ['webp', 'gif']);
        $this->assertFormatsComeFrom('media.documents', $upload, 'image');
    }

    public function test_a_shelf_photograph_accepts_only_the_formats_the_server_can_decode(): void
    {
        $upload = fn (UploadedFile $file): TestResponse => $this->postJson(
            '/api/v1/shelf-reads',
            ['photo' => $file],
        );

        $this->assertFormats($upload, 'photo', accepts: ['jpg', 'png'], refuses: ['webp', 'gif']);
        $this->assertFormatsComeFrom('media.documents', $upload, 'photo');
    }

    public function test_a_location_photograph_accepts_the_formats_a_client_can_render(): void
    {
        $location = Location::create(['name' => 'Fridge']);

        $upload = fn (UploadedFile $file): TestResponse => $this->putJson(
            "/api/v1/locations/{$location->getKey()}/image",
            ['image' => $file],
        );

        // `webp` is the whole point of this row: this path stores the bytes and a client renders
        // them, so it takes the wider list the two decoding paths above refuse.
        $this->assertFormats($upload, 'image', accepts: ['jpg', 'png', 'webp'], refuses: ['gif']);
        $this->assertFormatsComeFrom('media.images', $upload, 'image');
    }

    public function test_a_gallery_picture_accepts_the_formats_a_client_can_render(): void
    {
        $product = Product::create(['name' => 'Süt']);

        $upload = fn (UploadedFile $file): TestResponse => $this->postJson(
            "/api/v1/products/{$product->getKey()}/images",
            ['image' => $file],
        );

        $this->assertFormats($upload, 'image', accepts: ['jpg', 'png', 'webp'], refuses: ['gif']);
        $this->assertFormatsComeFrom('media.images', $upload, 'image');
    }

    /**
     * Every format this endpoint admits, and the nearest ones it does not.
     *
     * Acceptance is asserted as "no error naming the field" rather than as a status, because what
     * happens AFTER a valid upload differs per endpoint and is somebody else's test: a receipt whose
     * bytes hash to one already stored answers 409, and a photograph read with no credits answers 200
     * with no card. Both mean the format was admitted.
     *
     * @param  Closure(UploadedFile): TestResponse  $upload
     * @param  list<string>  $accepts
     * @param  list<string>  $refuses
     */
    private function assertFormats(Closure $upload, string $field, array $accepts, array $refuses): void
    {
        foreach ($accepts as $extension) {
            $upload(UploadedFile::fake()->image("picture.{$extension}"))
                ->assertJsonMissingValidationErrors($field);
        }

        foreach ($refuses as $extension) {
            $upload(UploadedFile::fake()->image("picture.{$extension}"))
                ->assertStatus(422)
                ->assertJsonValidationErrors($field);
        }
    }

    /**
     * Which config block this endpoint's format list actually comes from.
     *
     * Narrowing a block to `png` and posting a JPEG is the only instrument that separates the three
     * lists, because two of them hold identical values today. The second half is the half that
     * catches a merge: the other two blocks are narrowed and this endpoint has to be unmoved.
     *
     * @param  Closure(UploadedFile): TestResponse  $upload
     */
    private function assertFormatsComeFrom(string $block, Closure $upload, string $field): void
    {
        $original = [];

        foreach (self::BLOCKS as $candidate) {
            $original[$candidate] = config("{$candidate}.mimes");
        }

        config(["{$block}.mimes" => ['png']]);

        $upload(UploadedFile::fake()->image('picture.jpg'))
            ->assertStatus(422)
            ->assertJsonValidationErrors($field);

        foreach (self::BLOCKS as $candidate) {
            config(["{$candidate}.mimes" => $candidate === $block ? $original[$candidate] : ['png']]);
        }

        $upload(UploadedFile::fake()->image('picture.jpg'))
            ->assertJsonMissingValidationErrors($field);
    }
}
