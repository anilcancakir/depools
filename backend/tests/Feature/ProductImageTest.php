<?php

namespace Tests\Feature;

use App\Models\Barcode;
use App\Models\GlobalProduct;
use App\Models\Product;
use App\Models\ProductImage;
use App\Models\Team;
use App\Models\User;
use Illuminate\Database\QueryException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Facades\URL;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * A product's pictures: what a client is answered, and what the gallery refuses.
 *
 * The interesting assertion is rarely that a field appears. It is that ONE KIND of thing appears in
 * it: a picture on our disk and a picture we only link to arrive as the same loadable url, because
 * `ProductCandidate` and `ProductImageResource` each carry a single field and a client has to be able
 * to load whatever comes out of it.
 */
final class ProductImageTest extends TestCase
{
    use RefreshDatabase;

    private User $user;

    private Team $team;

    protected function setUp(): void
    {
        parent::setUp();

        /** @var User $user */
        $user = User::factory()->createOne(['locale' => 'en']);
        $team = Team::create(['name' => 'Alpha', 'user_id' => $user->getKey()]);
        $user->forceFill(['current_team_id' => $team->getKey()])->save();

        $this->user = $user->refresh();
        $this->team = $team;

        $this->actingAs($this->user, 'sanctum');
    }

    /** A product carrying one picture, which is the shape most of these tests start from. */
    private function productWithPicture(string $path = 'product-images/milk.jpg'): Product
    {
        $product = Product::create(['name' => 'Süt']);

        $image = $product->images()->create(['path' => $path, 'source' => 'upload']);
        $product->makeImagePrimary($image);

        return $product->refresh();
    }

    /**
     * Fake the media disk without throwing away the config that shapes its urls.
     *
     * **`Storage::fake` carries only `throw` from the real disk**, so a bare fake drops the `url` key
     * and every generated url reverts to the `/storage` fallback. That is how these tests kept passing
     * while D120 moved the served path to `/media`: they agreed with a config they had stopped reading.
     * Handing the two url-shaping settings back makes them exercise the real path shape again, and
     * reading them from the config rather than writing them out is what makes them follow the next move.
     */
    private function fakeMediaDisk(): string
    {
        $disk = config('media.images.disk');

        Storage::fake($disk, [
            'url' => config("filesystems.disks.{$disk}.url"),
            'visibility' => config("filesystems.disks.{$disk}.visibility"),
        ]);

        return $disk;
    }

    /**
     * The disk path behind a url a client was answered.
     *
     * **Derived from the config rather than written out, because the served path MOVED once already.**
     * These assertions used to strip a literal `url('/storage')`, and D120 put the public disk at
     * `/media`. They kept passing anyway, which is the part worth naming: a green test that agrees
     * with a config it is no longer reading is worse than a red one.
     *
     * **Stripped from the PATH rather than by replacing a base string, because `Storage::fake` builds
     * two different urls.** Measured: a faked disk's `url()` honours the `url` key and answers
     * `/media/<path>`, while its `temporaryUrl()` is a stub that drops the base entirely and answers
     * `/<path>?expiration=...` with no signature at all. A helper that stripped the `/media` base
     * therefore worked on one and silently returned the whole url on the other, which is how three
     * assertions here read null instead of bytes.
     */
    private function diskPathOf(string $url, ?string $disk = null): string
    {
        $name = $disk ?? config('media.images.disk');
        $path = (string) parse_url($url, PHP_URL_PATH);
        $prefix = (string) parse_url((string) config("filesystems.disks.{$name}.url"), PHP_URL_PATH);

        if ($prefix !== '' && str_starts_with($path, $prefix)) {
            $path = substr($path, strlen($prefix));
        }

        return ltrim($path, '/');
    }

    /**
     * That a media url carries a signature, which is the whole point of this change.
     *
     * Asserted as the presence of both parameters rather than by re-deriving the hash: recomputing it
     * here would use the same code that produced it, so the test would pass on a broken signer. What
     * proves the signature is CHECKED is the request test at the bottom of this file, which fetches a
     * signed url and an unsigned one and compares the statuses.
     */
    private function assertSignedUrl(string $url): void
    {
        parse_str((string) parse_url($url, PHP_URL_QUERY), $query);

        $this->assertArrayHasKey('expires', $query, "[$url] carries no expiry, so it never dies");
        $this->assertArrayHasKey('signature', $query, "[$url] is unsigned, so anyone holding it can read a tenant's photograph");
    }

    public function test_a_stored_path_is_answered_as_a_url(): void
    {
        // The path is ours and means nothing to a client; the field is called `image_url` and should be
        // one. The exact base is configuration and pinning it would make this a test about `.env`, so
        // what is asserted is the property the NAME promises: a scheme and a host.
        //
        // **An earlier version asserted only that the string was not the bare path, and that was not
        // enough.** The local disk answers `/storage/<path>`, which passed that while loading nowhere:
        // a Flutter mobile build throws `No host specified in URI` and a web build resolves it against
        // its own origin. A weaker assertion here is what let it reach master once already.
        $url = $this->productWithPicture()->image_url;

        $this->assertIsString($url);
        // **Ends-with on the PATH, not contains on the whole url.** The suffix assertion was right
        // while the url was unsigned and a signature now follows the path, so it had to move rather
        // than weaken: `contains` would also pass on a path that appeared only inside the query.
        $this->assertStringEndsWith('product-images/milk.jpg', (string) parse_url($url, PHP_URL_PATH));
        $this->assertNotNull(parse_url($url, PHP_URL_SCHEME), "[$url] has no scheme");
        $this->assertNotNull(parse_url($url, PHP_URL_HOST), "[$url] has no host, so no client can load it");
        $this->assertSignedUrl($url);
    }

    public function test_a_linked_picture_is_answered_as_it_stands(): void
    {
        // Not ours, so nothing to convert. An Open Food Facts photograph is CC-BY-SA and D87 keeps it
        // at arm's length, so the gallery points at it rather than holding it.
        $product = Product::create(['name' => 'Ayran']);

        $image = $product->images()->create([
            'remote_url' => 'https://images.openfoodfacts.org/front_en.jpg',
            'source' => 'link',
            'attribution' => 'Open Food Facts contributors, CC-BY-SA 3.0',
        ]);

        $this->assertSame('https://images.openfoodfacts.org/front_en.jpg', $image->url);
    }

    public function test_a_product_with_no_pictures_answers_null_rather_than_a_url_to_nothing(): void
    {
        $product = Product::create(['name' => 'Süt']);

        $this->assertNull($product->image_url);
    }

    public function test_the_database_refuses_a_blank_path(): void
    {
        // **A blank is not a source of bytes**, and the first version of the CHECK let it through: an
        // empty string is not NULL, so `path = '   '` satisfied "exactly one is set" while being as
        // unloadable as nothing at all. The constraint folds the whitespace now, so this is refused
        // rather than stored and rendered as a broken box.
        $product = Product::create(['name' => 'Süt']);

        $this->expectException(QueryException::class);

        DB::transaction(function () use ($product): void {
            $product->images()->create(['path' => '   ', 'source' => 'upload']);
        });
    }

    public function test_the_product_resource_carries_the_primary_url_and_the_gallery(): void
    {
        $product = $this->productWithPicture();
        $product->images()->create(['path' => 'product-images/back.jpg', 'source' => 'upload', 'position' => 1]);

        $this->getJson("/api/v1/products/{$product->getKey()}")
            ->assertOk()
            ->assertJsonPath('data.image_url', $product->image_url)
            ->assertJsonCount(2, 'data.images')
            ->assertJsonPath('data.images.0.is_primary', true)
            ->assertJsonPath('data.images.1.is_primary', false);
    }

    public function test_a_scan_of_the_tenants_own_product_carries_its_picture(): void
    {
        // Stage 1 sent no image at all, so the row we know MOST about looked like the one we knew
        // least about: a catalogue hit showed a photograph and the tenant's own product showed nothing.
        $product = $this->productWithPicture();
        $product->linkBarcode(Barcode::forGtin('8690504004073'));

        $this->getJson('/api/v1/barcode/resolve?code=8690504004073')
            ->assertOk()
            ->assertJsonPath('data.source', 'own')
            ->assertJsonPath('data.image_url', $product->image_url);
    }

    public function test_a_catalogue_hit_answers_a_url_and_not_the_stored_path(): void
    {
        // `global_products.image_path` is a path on our disk, and the resolver used to pass it straight
        // into a field named `image_url`. Nothing broke while the client ignored it.
        $barcode = Barcode::forGtin('8690632073415');

        $global = GlobalProduct::create([
            'name' => 'Sütaş Ayran 250 ml',
            'locale' => 'en',
            'source' => 'community',
            'confidence' => 70,
            'image_path' => 'catalogue/ayran.jpg',
        ]);

        $global->barcodes()->syncWithoutDetaching([$barcode->getKey()]);

        $body = $this->getJson('/api/v1/barcode/resolve?code=8690632073415')->assertOk()->json('data');

        $this->assertSame('community', $body['source']);
        $this->assertNotSame('catalogue/ayran.jpg', $body['image_url'], 'a path cannot be loaded');
        $this->assertStringEndsWith('catalogue/ayran.jpg', (string) parse_url($body['image_url'], PHP_URL_PATH));
        $this->assertSignedUrl($body['image_url']);
    }

    public function test_the_first_picture_becomes_the_primary_and_the_second_does_not(): void
    {
        // A gallery with no primary renders as a product with no picture, and asking which of one
        // picture should lead is a question with a single answer.
        $this->fakeMediaDisk();

        $product = Product::create(['name' => 'Süt']);

        $first = $this->postJson("/api/v1/products/{$product->getKey()}/images", [
            'image' => UploadedFile::fake()->image('front.jpg'),
        ])->assertCreated()->json('data');

        $second = $this->postJson("/api/v1/products/{$product->getKey()}/images", [
            'image' => UploadedFile::fake()->image('back.jpg'),
        ])->assertCreated()->json('data');

        $this->assertTrue($first['is_primary']);
        $this->assertFalse($second['is_primary']);
        $this->assertSame(0, $first['position']);
        $this->assertSame(1, $second['position']);

        Storage::disk(config('media.images.disk'))->assertExists(
            $this->diskPathOf($first['url'])
        );
    }

    public function test_promoting_a_picture_demotes_the_one_that_held_it(): void
    {
        $product = $this->productWithPicture();
        $second = $product->images()->create(['path' => 'product-images/back.jpg', 'source' => 'upload', 'position' => 1]);

        $this->patchJson("/api/v1/products/{$product->getKey()}/images/{$second->getKey()}", [
            'is_primary' => true,
        ])->assertOk()->assertJsonPath('data.is_primary', true);

        // One primary, and it is the new one. Reading the COUNT rather than the first row, because the
        // partial unique index is what stops two, and a test that only checked the new row would pass
        // with the old one still set.
        $this->assertSame(1, $product->images()->where('is_primary', true)->count());
        $this->assertTrue($second->refresh()->is_primary);
    }

    public function test_deleting_the_primary_hands_the_primacy_on(): void
    {
        // Otherwise the list row goes blank while the detail screen still shows two photographs, which
        // reads as data loss rather than as a deletion.
        $product = $this->productWithPicture();
        $primary = $product->primaryImage;
        $second = $product->images()->create(['path' => 'product-images/back.jpg', 'source' => 'upload', 'position' => 1]);

        $this->deleteJson("/api/v1/products/{$product->getKey()}/images/{$primary->getKey()}")
            ->assertNoContent();

        $this->assertTrue($second->refresh()->is_primary);
        $this->assertNotNull($product->refresh()->image_url);
    }

    public function test_deleting_the_only_picture_leaves_the_product_without_one(): void
    {
        $product = $this->productWithPicture();

        $this->deleteJson("/api/v1/products/{$product->getKey()}/images/{$product->primaryImage->getKey()}")
            ->assertNoContent();

        $this->assertNull($product->refresh()->image_url);
        $this->assertSame(0, $product->images()->count());
    }

    public function test_a_link_is_recorded_without_being_fetched(): void
    {
        $product = Product::create(['name' => 'Ayran']);

        $body = $this->postJson("/api/v1/products/{$product->getKey()}/images", [
            'url' => 'https://images.openfoodfacts.org/front_en.jpg',
            'attribution' => 'Open Food Facts contributors, CC-BY-SA 3.0',
        ])->assertCreated()->json('data');

        $this->assertSame('https://images.openfoodfacts.org/front_en.jpg', $body['url']);
        $this->assertSame('link', $body['source']);
        $this->assertSame('Open Food Facts contributors, CC-BY-SA 3.0', $body['attribution']);
    }

    public function test_an_insecure_link_is_refused(): void
    {
        // It would be a mixed-content block on the web build, so it is a picture that could never
        // render. Refused at the boundary rather than stored and puzzled over later.
        $product = Product::create(['name' => 'Ayran']);

        $this->postJson("/api/v1/products/{$product->getKey()}/images", [
            'url' => 'http://images.openfoodfacts.org/front_en.jpg',
        ])->assertStatus(422)->assertJsonValidationErrors('url');
    }

    public function test_a_request_naming_no_picture_is_refused(): void
    {
        $product = Product::create(['name' => 'Süt']);

        $this->postJson("/api/v1/products/{$product->getKey()}/images", [])
            ->assertStatus(422);
    }

    public function test_a_catalogue_picture_is_copied_onto_our_own_disk(): void
    {
        // Copied rather than linked, and the difference is the licence: `CatalogueContributor` keeps
        // `image_path` null for anything derived from Open Food Facts, so a file in that column is one
        // we may redistribute.
        $disk = config('media.images.disk');

        $this->fakeMediaDisk();
        Storage::fake(config('filesystems.default'));
        Storage::disk(config('filesystems.default'))->put('catalogue/ayran.jpg', 'the bytes');

        $global = GlobalProduct::create([
            'name' => 'Sütaş Ayran 250 ml',
            'locale' => 'en',
            'source' => 'community',
            'confidence' => 70,
            'image_path' => 'catalogue/ayran.jpg',
        ]);

        $product = Product::create(['name' => 'Ayran']);
        $product->forceFill(['global_product_id' => $global->getKey()])->save();

        $body = $this->postJson("/api/v1/products/{$product->getKey()}/images", [
            'from_catalogue' => true,
        ])->assertCreated()->json('data');

        $this->assertSame('catalogue', $body['source']);
        $this->assertSame(
            'the bytes',
            Storage::disk($disk)->get($this->diskPathOf($body['url'], $disk))
        );
    }

    public function test_a_catalogue_copy_with_nothing_to_copy_is_refused(): void
    {
        $product = Product::create(['name' => 'Süt']);

        $this->postJson("/api/v1/products/{$product->getKey()}/images", ['from_catalogue' => true])
            ->assertStatus(422)
            ->assertJsonValidationErrors('from_catalogue');
    }

    public function test_a_catalogue_row_pointing_at_a_file_that_is_gone_is_refused(): void
    {
        // A recorded path is not a file. A takedown that removed the bytes, a stale row or a disk
        // restored without them all land here, and the user asked for something that is not there,
        // which is a 422 and not a 500.
        //
        // Measured before it was fixed: the disk carries `throw => false`, so `get()` answered NULL
        // and the exception came one line later out of Flysystem's `write()` as
        // `Argument #2 ($contents) must be of type string, null given`.
        $this->fakeMediaDisk();
        Storage::fake(config('filesystems.default'));

        $global = GlobalProduct::create([
            'name' => 'Sütaş Ayran 250 ml',
            'locale' => 'en',
            'source' => 'community',
            'confidence' => 70,
            'image_path' => 'catalogue/removed.jpg',
        ]);

        $product = Product::create(['name' => 'Ayran']);
        $product->forceFill(['global_product_id' => $global->getKey()])->save();

        $this->postJson("/api/v1/products/{$product->getKey()}/images", ['from_catalogue' => true])
            ->assertStatus(422)
            ->assertJsonValidationErrors('from_catalogue');
    }

    public function test_promoting_the_picture_that_already_leads_is_not_an_error(): void
    {
        // The idempotent case, and the one that shows the swap has to clear before it sets: the row
        // being promoted is the row being demoted, so an order that set first would collide with the
        // partial unique index against itself.
        $product = $this->productWithPicture();
        $primary = $product->primaryImage;

        $this->patchJson("/api/v1/products/{$product->getKey()}/images/{$primary->getKey()}", [
            'is_primary' => true,
        ])->assertOk()->assertJsonPath('data.is_primary', true);

        $this->assertSame(1, $product->images()->where('is_primary', true)->count());
    }

    public function test_a_delete_answers_with_no_body_at_all(): void
    {
        // A 204 carrying JSON is read inconsistently by proxies and clients. Symfony's `prepare`
        // strips it, so this holds whichever spelling the controller uses; the assertion is here so
        // that stays true rather than being a property of the framework nobody checked.
        $product = $this->productWithPicture();

        $response = $this->deleteJson("/api/v1/products/{$product->getKey()}/images/{$product->primaryImage->getKey()}");

        $response->assertNoContent();
        $this->assertSame('', $response->getContent());
    }

    public function test_a_new_picture_lands_after_the_last_one_rather_than_at_the_count(): void
    {
        // The two are the same number only while the sequence is dense. `update` accepts any position
        // up to the ceiling, so a gallery of two whose second picture was moved to 7 would otherwise
        // take 2 for its next upload and put an appended picture in the middle.
        $product = $this->productWithPicture();
        $second = $product->images()->create(['path' => 'product-images/back.jpg', 'source' => 'upload', 'position' => 1]);

        $this->patchJson("/api/v1/products/{$product->getKey()}/images/{$second->getKey()}", ['position' => 7])
            ->assertOk();

        $body = $this->postJson("/api/v1/products/{$product->getKey()}/images", [
            'url' => 'https://example.com/third.jpg',
        ])->assertCreated()->json('data');

        $this->assertSame(8, $body['position']);
    }

    public function test_the_gallery_stops_at_its_ceiling(): void
    {
        $product = Product::create(['name' => 'Süt']);

        for ($i = 0; $i < ProductImage::MAX_PER_PRODUCT; $i++) {
            $product->images()->create(['path' => "product-images/{$i}.jpg", 'source' => 'upload', 'position' => $i]);
        }

        $this->postJson("/api/v1/products/{$product->getKey()}/images", [
            'url' => 'https://example.com/one-too-many.jpg',
        ])->assertStatus(422)->assertJsonValidationErrors('image');
    }

    public function test_another_tenants_product_is_not_found_rather_than_forbidden(): void
    {
        // Written before the feature it protects, and asserting 404: a 403 would confirm the product
        // exists, which is itself a leak across tenants.
        /** @var User $other */
        $other = User::factory()->createOne();
        $theirTeam = Team::create(['name' => 'Beta', 'user_id' => $other->getKey()]);
        $other->forceFill(['current_team_id' => $theirTeam->getKey()])->save();

        $this->actingAs($other->refresh(), 'sanctum');
        $theirs = $this->productWithPicture();
        $theirPicture = $theirs->primaryImage;

        $this->actingAs($this->user, 'sanctum');

        $this->postJson("/api/v1/products/{$theirs->getKey()}/images", [
            'url' => 'https://example.com/mine.jpg',
        ])->assertNotFound();

        $this->patchJson("/api/v1/products/{$theirs->getKey()}/images/{$theirPicture->getKey()}", [
            'is_primary' => true,
        ])->assertNotFound();

        $this->deleteJson("/api/v1/products/{$theirs->getKey()}/images/{$theirPicture->getKey()}")
            ->assertNotFound();

        // And the picture survived all three, which is the assertion that would catch a route that
        // 404s on the way out AFTER doing the work.
        $this->assertSame(1, $theirs->images()->withoutGlobalScopes()->count());
    }

    public function test_a_picture_from_another_product_cannot_be_promoted_here(): void
    {
        // Same tenant, so the scope permits both rows; this is the guard the scope does not cover.
        $mine = $this->productWithPicture();
        $other = $this->productWithPicture('product-images/other.jpg');

        $this->patchJson("/api/v1/products/{$mine->getKey()}/images/{$other->primaryImage->getKey()}", [
            'is_primary' => true,
        ])->assertNotFound();
    }

    public function test_the_database_refuses_two_primaries(): void
    {
        $product = $this->productWithPicture();
        $second = $product->images()->create(['path' => 'product-images/back.jpg', 'source' => 'upload', 'position' => 1]);

        $this->expectException(QueryException::class);

        // Its own savepoint, because PostgreSQL aborts the whole transaction on a constraint violation
        // and every later query in this test would fail with `25P02` instead.
        DB::transaction(function () use ($second): void {
            $second->forceFill(['is_primary' => true])->save();
        });
    }

    public function test_the_database_refuses_a_row_that_is_neither_ours_nor_theirs(): void
    {
        $product = Product::create(['name' => 'Süt']);

        $this->expectException(QueryException::class);

        DB::transaction(function () use ($product): void {
            $product->images()->create(['source' => 'upload']);
        });
    }

    public function test_the_database_refuses_a_row_that_claims_to_be_both(): void
    {
        $product = Product::create(['name' => 'Süt']);

        $this->expectException(QueryException::class);

        DB::transaction(function () use ($product): void {
            $product->images()->create([
                'path' => 'product-images/milk.jpg',
                'remote_url' => 'https://example.com/milk.jpg',
                'source' => 'upload',
            ]);
        });
    }

    public function test_a_stored_picture_is_served_by_laravel_and_carries_a_cross_origin_header(): void
    {
        // **A Flutter WEB build fetches image bytes through XHR, so a picture without an
        // `Access-Control-Allow-Origin` header is refused and the gallery falls back to an initial.**
        // Measured on the product screen, where the Open Food Facts photograph rendered and ours did
        // not, the only difference between them being that header.
        //
        // Three separate things have to hold for that, and each of them is a one-line config change
        // away from silently breaking a picture, which is why they are asserted together here rather
        // than trusted: the disk is SERVED by Laravel (so a request reaches the middleware at all),
        // `media/*` is in the CORS paths (so the middleware answers), and the url carries a valid
        // SIGNATURE (so `ServeFile` serves it rather than refusing).
        //
        // A symlink at `public/storage` would defeat the first: the web server answers a file it can
        // see before the router runs. `bin/check` removes one rather than making one now.
        //
        // **The third condition used to be `visibility => public` and is now its opposite** (D128).
        // That setting made `ServeFile` skip the signature check entirely, and this test was quietly
        // certifying the hole: it fetched a url with no signature and asserted 200. Do NOT restore it
        // to fix a broken gallery; a gallery breaks here when the SIGNATURE is missing, which is what
        // the second half of this test now proves by asking for the same file without one.
        //
        // **It runs on the REAL disk, not `Storage::fake`, and that is forced rather than chosen.**
        // Measured: a faked disk honours the `url` key for `url()` and answers `/media/<path>`, while
        // its `temporaryUrl()` is a stub that drops the base and appends `?expiration=` with NO
        // signature. A fake therefore cannot express the property this test exists for.
        $disk = config('media.images.disk');
        $path = 'product-images/'.Str::uuid7()->toString().'.jpg';

        Storage::disk($disk)->put($path, 'not really a jpeg');

        try {
            $product = $this->productWithPicture($path);
            $signed = (string) $product->image_url;

            $response = $this->get($signed, ['Origin' => 'http://localhost:3000']);

            $response->assertOk();
            $this->assertSame('not really a jpeg', $response->streamedContent());
            $this->assertSame('*', $response->headers->get('Access-Control-Allow-Origin'), "[$signed] is not readable from a web build");

            // The same file, same route, no signature: refused. 403 in development and 404 in
            // production, which `ServeFile` picks by environment, so the assertion allows either
            // rather than pinning the one this suite happens to run under.
            $unsigned = $this->get((string) parse_url($signed, PHP_URL_PATH), ['Origin' => 'http://localhost:3000']);

            $this->assertContains(
                $unsigned->getStatusCode(),
                [403, 404],
                'an unsigned media url was served, which is the hole signing exists to close',
            );
        } finally {
            Storage::disk($disk)->delete($path);
        }
    }

    public function test_a_picture_belongs_to_the_team_that_owns_the_product(): void
    {
        // `team_id` is stamped from the auth context and is not fillable, so this is really a check
        // that the concern is on the model at all: without it the insert would fail NOT NULL, and with
        // it pointed anywhere else the gallery would be invisible to its own product.
        $product = $this->productWithPicture();

        $this->assertSame($this->team->getKey(), $product->primaryImage->team_id);
    }
}
