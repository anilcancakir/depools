<?php

namespace Tests\Feature;

use App\Models\Barcode;
use App\Models\GlobalProduct;
use App\Models\OffProduct;
use App\Models\Product;
use App\Models\Team;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * A product's picture, from wherever the cascade found it.
 *
 * The interesting assertion is not that a field appears, but that ONE KIND of thing appears in it. Two
 * of the three sources store a path on our disk and the third stores a remote url on purpose, because
 * an Open Food Facts photograph is CC-BY-SA and deliberately not redistributed. `ProductCandidate` has
 * a single `image_url`, so a client reading it has to be able to load whatever arrives.
 */
final class ProductImageTest extends TestCase
{
    use RefreshDatabase;

    private User $user;

    protected function setUp(): void
    {
        parent::setUp();

        /** @var User $user */
        $user = User::factory()->createOne(['locale' => 'en']);
        $team = Team::create(['name' => 'Alpha', 'user_id' => $user->getKey()]);
        $user->forceFill(['current_team_id' => $team->getKey()])->save();

        $this->user = $user->refresh();

        $this->actingAs($this->user, 'sanctum');
    }

    public function test_a_stored_path_is_answered_as_a_url(): void
    {
        // The path is ours and means nothing to a client; the field is called `image_url` and should be
        // one. The exact base is configuration and pinning it would make this a test about `.env`, so
        // what is asserted is the property the NAME promises: a scheme and a host.
        //
        // **The first version of this asserted only that the string was not the bare path, and that was
        // not enough.** The local disk answers `/storage/products/milk.jpg`, which passed all three of
        // the old assertions and loads nowhere: a Flutter mobile build throws `No host specified in
        // URI` and a web build resolves it against its own origin. A weaker assertion here is what let
        // that reach master.
        $product = Product::create(['name' => 'Süt', 'image_path' => 'products/milk.jpg']);

        $url = $product->image_url;

        $this->assertIsString($url);
        $this->assertStringEndsWith('products/milk.jpg', $url);
        $this->assertNotNull(parse_url($url, PHP_URL_SCHEME), "[$url] has no scheme");
        $this->assertNotNull(parse_url($url, PHP_URL_HOST), "[$url] has no host, so no client can load it");
    }

    public function test_a_product_with_no_image_answers_null_rather_than_a_url_to_nothing(): void
    {
        $product = Product::create(['name' => 'Süt']);

        $this->assertNull($product->image_url);

        // And a blank string is the same as none, because that is what an emptied form field leaves.
        $product->forceFill(['image_path' => '   '])->save();

        $this->assertNull($product->refresh()->image_url);
    }

    public function test_the_product_resource_carries_the_url(): void
    {
        // The column existed from the first migration and nothing exposed it, so no screen could show a
        // picture even for a product that had one.
        $product = Product::create(['name' => 'Süt', 'image_path' => 'products/milk.jpg']);

        $this->getJson("/api/v1/products/{$product->getKey()}")
            ->assertOk()
            ->assertJsonPath('data.image_url', $product->image_url);
    }

    public function test_a_scan_of_the_tenants_own_product_carries_its_picture(): void
    {
        // Stage 1 sent no image at all, so the row we know MOST about looked like the one we knew least
        // about: a catalogue hit showed a photograph and the tenant's own product showed nothing.
        $product = Product::create(['name' => 'Süt', 'image_path' => 'products/milk.jpg']);
        $product->linkBarcode(Barcode::forGtin('8690504004073'));

        $this->getJson('/api/v1/barcode/resolve?code=8690504004073')
            ->assertOk()
            ->assertJsonPath('data.source', 'own')
            ->assertJsonPath('data.image_url', $product->image_url);
    }

    public function test_a_catalogue_hit_answers_a_url_and_not_the_stored_path(): void
    {
        // `global_products.image_path` is a path on our disk, and the resolver used to pass it straight
        // into a field named `image_url`. Nothing broke while the client ignored it; wiring the client
        // is what would have put a path into an image tag.
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
        $this->assertStringEndsWith('catalogue/ayran.jpg', $body['image_url']);
    }

    public function test_an_open_food_facts_hit_keeps_its_remote_url_untouched(): void
    {
        // The other half of the same question. That photograph is CC-BY-SA and deliberately NOT copied
        // to our disk, so its url is somebody else's and must pass through exactly as stored: rewriting
        // it through our own disk would produce a url to a file we do not have.
        OffProduct::create([
            'gtin' => '04001200296908',
            'name' => 'Remote Product',
            'locale' => 'en',
            'image_url' => 'https://images.openfoodfacts.org/remote.jpg',
            'source_ref' => '4001200296908',
            'imported_at' => now(),
        ]);

        $this->getJson('/api/v1/barcode/resolve?code=4001200296908')
            ->assertOk()
            ->assertJsonPath('data.source', 'off')
            ->assertJsonPath('data.image_url', 'https://images.openfoodfacts.org/remote.jpg');
    }
}
