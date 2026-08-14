<?php

namespace Tests\Feature;

use App\Enums\MovementReason;
use App\Models\Barcode;
use App\Models\GlobalProduct;
use App\Models\Location;
use App\Models\Product;
use App\Models\ProductStock;
use App\Models\StockMovement;
use App\Models\Team;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Testing\TestResponse;
use Tests\TestCase;

/**
 * Receiving a whole scan batch into one location.
 *
 * The endpoint does two things no other stock endpoint does: it takes a LIST, and it CREATES the
 * products a catalogue line names. Both are load-bearing, so the assertions here are mostly about
 * what must not happen at the seam between them: a product created with no stock against it, stock
 * written for a product that failed to be created, or a foreign identifier reaching the ledger.
 */
final class ScanBatchTest extends TestCase
{
    use RefreshDatabase;

    private Location $shelf;

    /** @return array{0: User, 1: Team} */
    private function tenant(string $name = 'Alpha'): array
    {
        /** @var User $user */
        $user = User::factory()->createOne(['locale' => 'tr']);
        $team = Team::create(['name' => $name, 'user_id' => $user->getKey()]);
        $user->forceFill(['current_team_id' => $team->getKey()])->save();
        $user->refresh();

        $this->actingAs($user, 'sanctum');

        return [$user, $team];
    }

    protected function setUp(): void
    {
        parent::setUp();

        $this->tenant();
        $this->shelf = Location::create(['name' => 'Raf A']);
    }

    /**
     * @param  array<int, array<string, mixed>>  $lines
     */
    private function receive(array $lines, ?string $locationId = null): TestResponse
    {
        return $this->postJson('/api/v1/stock/receive-batch', [
            'location_id' => $locationId ?? $this->shelf->getKey(),
            'lines' => $lines,
        ]);
    }

    public function test_a_product_the_tenant_owns_is_stocked_without_being_recreated(): void
    {
        $milk = Product::create(['name' => 'Süt', 'base_unit' => 'adet']);

        $this->receive([
            ['product_id' => $milk->getKey(), 'quantity' => 3],
        ])->assertCreated()->assertJsonPath('data.lines.0.created', false);

        $this->assertSame(1, Product::query()->count());
        $this->assertSame('3.000', ProductStock::query()->sole()->quantity);
    }

    public function test_a_catalogue_line_becomes_a_product_and_its_stock_in_one_request(): void
    {
        // **The whole reason this endpoint creates anything.** The cascade answers what a barcode IS,
        // and for a community or Open Food Facts hit the tenant owns no product for it. Sending them
        // to a form for every carton the community already described is the alternative.
        $this->receive([
            ['name' => 'Pınar Süt 1 L', 'brand' => 'Pınar', 'base_unit' => 'adet',
                'barcode' => '8690504010012', 'quantity' => 2],
        ])->assertCreated()->assertJsonPath('data.lines.0.created', true);

        $product = Product::query()->sole();
        $this->assertSame('Pınar Süt 1 L', $product->name);
        $this->assertSame('2.000', ProductStock::query()->sole()->quantity);
        // Linked, or the next scan of the same carton misses and creates a second product.
        $this->assertTrue($product->barcodes()->where('gtin', '08690504010012')->exists());
    }

    public function test_a_created_line_contributes_to_the_catalogue_by_default(): void
    {
        // D117: the box is ticked, and a batch is exactly where the moat fills fastest.
        $this->receive([
            ['name' => 'Pınar Süt 1 L', 'barcode' => '8690504010012', 'quantity' => 1],
        ])->assertCreated();

        $this->assertSame('community', GlobalProduct::query()->sole()->source);
    }

    public function test_unticking_the_box_on_a_line_contributes_nothing(): void
    {
        $this->receive([
            ['name' => 'Gizli Tarif', 'barcode' => '8690504010012', 'quantity' => 1,
                'contribute' => false],
        ])->assertCreated();

        $this->assertSame(0, GlobalProduct::query()->count());
        // The product and its stock are unaffected: the box is about sharing, not saving.
        $this->assertSame(1, Product::query()->count());
    }

    public function test_a_missing_unit_defaults_to_the_countable_one(): void
    {
        // A catalogue row carries no unit, deliberately: what a product is COUNTED in is the tenant's
        // decision. Refusing the carton for a field the catalogue never had would be worse.
        $this->receive([
            ['name' => 'Bir şey', 'quantity' => 1],
        ])->assertCreated();

        $this->assertSame('piece', Product::query()->sole()->base_unit);
    }

    public function test_a_line_with_neither_a_product_nor_a_name_is_refused(): void
    {
        $this->receive([['quantity' => 1]])
            ->assertStatus(422)
            ->assertJsonValidationErrors(['lines.0.product_id', 'lines.0.name']);

        $this->assertSame(0, StockMovement::query()->count());
    }

    public function test_another_tenants_product_is_a_404_that_wrote_nothing(): void
    {
        // Tenancy rule 2, and it has to stay a 404: a 403 confirms the identifier is real, which is
        // how an attacker holding a range of ids maps another tenant's catalogue without reading one.
        $mine = Product::create(['name' => 'Süt', 'base_unit' => 'adet']);

        $this->tenant('Beta');
        $theirs = Product::create(['name' => 'Beta Süt', 'base_unit' => 'adet']);

        $this->tenant('Alpha');
        $shelf = Location::create(['name' => 'Raf B']);

        $this->receive([
            ['product_id' => $mine->getKey(), 'quantity' => 1],
            ['product_id' => $theirs->getKey(), 'quantity' => 1],
        ], $shelf->getKey())->assertNotFound();

        // **Nothing at all, including the line BEFORE the foreign one.** The resolve happens before
        // the transaction opens, so a batch naming somebody else's product writes no movement rather
        // than half a delivery.
        $this->assertSame(0, StockMovement::query()->count());
    }

    public function test_a_batch_writes_every_line_or_none(): void
    {
        // The reason this is one request. A dropped connection halfway down a pile of boxes would
        // otherwise leave some stock written and no way to tell which without re-counting it.
        //
        // **The failing line is refused by the WRITER, not by validation**, and the first version of
        // this test got that wrong: it used `quantity: 0`, which never reaches the transaction
        // because `gt:0` rejects it first. The test passed and proved only that validation works. A
        // serial-tracked product is a real writer refusal (invariant 8: its quantity is the count of
        // its serials, so a lot here would be a second disagreeing answer), and it arrives with
        // everything already valid.
        $milk = Product::create(['name' => 'Süt', 'base_unit' => 'adet']);
        $serialised = Product::create([
            'name' => 'Telefon',
            'base_unit' => 'adet',
            'tracking_mode' => 'serial',
        ]);

        $this->receive([
            ['product_id' => $milk->getKey(), 'quantity' => 2],
            ['name' => 'Yeni Ürün', 'barcode' => '8690504010012', 'quantity' => 5],
            ['product_id' => $serialised->getKey(), 'quantity' => 1],
        ])->assertStatus(422);

        $this->assertSame(0, StockMovement::query()->count(), 'the two lines before it rolled back');
        $this->assertSame(2, Product::query()->count(), 'and so did the product the batch created');
    }

    public function test_every_line_lands_as_a_purchase(): void
    {
        // Everything arriving through a receiving bench was bought. Letting a client name the reason
        // would put `correction` or `found` on a delivery, which is the audit distinction the ledger
        // exists to keep.
        $milk = Product::create(['name' => 'Süt', 'base_unit' => 'adet']);

        $this->receive([['product_id' => $milk->getKey(), 'quantity' => 4]])->assertCreated();

        $this->assertSame(MovementReason::Purchase, StockMovement::query()->sole()->reason);
    }

    public function test_a_barcode_this_tenant_already_uses_is_refused_before_anything_is_written(): void
    {
        $existing = Product::create(['name' => 'Süt', 'base_unit' => 'adet']);
        $existing->linkBarcode(Barcode::forGtin('8690504010012'));

        $this->receive([
            ['name' => 'İkinci Süt', 'barcode' => '8690504010012', 'quantity' => 1],
        ])->assertStatus(422)->assertJsonValidationErrors('barcode');

        $this->assertSame(1, Product::query()->count());
        $this->assertSame(0, StockMovement::query()->count());
    }

    public function test_the_last_receiving_location_is_where_the_last_delivery_went(): void
    {
        // Habit rather than affinity: a mixed batch cannot ask "where does this category go", and
        // where the last delivery was put away is a fact about how the business works.
        $other = Location::create(['name' => 'Kiler']);
        $milk = Product::create(['name' => 'Süt', 'base_unit' => 'adet']);

        $this->receive([['product_id' => $milk->getKey(), 'quantity' => 1]], $other->getKey())
            ->assertCreated();

        $this->getJson('/api/v1/stock/last-receiving-location')
            ->assertOk()
            ->assertJsonPath('data.location_id', $other->getKey());
    }

    public function test_putting_stock_away_does_not_move_the_default(): void
    {
        // **The filter on `purchase`, which nothing else here reaches.** Receiving and putting away
        // are two events (D38): the delivery lands where it was received and is moved onward
        // afterwards, so the transfer's inbound movement is MORE RECENT than the purchase and sits at
        // a different location. Without the filter the next delivery would default to wherever the
        // last thing happened to be carried, which is the shelf rather than the bench.
        $bench = Location::create(['name' => 'Kiler']);
        $milk = Product::create(['name' => 'Süt', 'base_unit' => 'adet']);

        $this->receive([['product_id' => $milk->getKey(), 'quantity' => 6]], $bench->getKey())
            ->assertCreated();

        $this->postJson('/api/v1/stock/transfer', [
            'product_id' => $milk->getKey(),
            'from_location_id' => $bench->getKey(),
            'to_location_id' => $this->shelf->getKey(),
            'quantity' => 2,
        ])->assertSuccessful();

        $this->getJson('/api/v1/stock/last-receiving-location')
            ->assertOk()
            ->assertJsonPath('data.location_id', $bench->getKey());
    }

    public function test_a_tenant_who_has_never_received_anything_gets_null(): void
    {
        // A first delivery is the ordinary case, so this is null and the client asks for a location
        // rather than showing an error.
        $this->getJson('/api/v1/stock/last-receiving-location')
            ->assertOk()
            ->assertJsonPath('data.location_id', null);
    }

    public function test_another_tenants_delivery_is_not_this_tenants_default(): void
    {
        $milk = Product::create(['name' => 'Süt', 'base_unit' => 'adet']);
        $this->receive([['product_id' => $milk->getKey(), 'quantity' => 1]])->assertCreated();

        $this->tenant('Beta');

        $this->getJson('/api/v1/stock/last-receiving-location')
            ->assertOk()
            ->assertJsonPath('data.location_id', null);
    }
}
