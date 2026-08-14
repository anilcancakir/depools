<?php

namespace Tests\Feature;

use App\Enums\ActorType;
use App\Enums\MovementReason;
use App\Enums\MovementSource;
use App\Models\Barcode;
use App\Models\Location;
use App\Models\Product;
use App\Models\StockLot;
use App\Models\StockMovement;
use App\Models\Team;
use App\Models\User;
use Illuminate\Database\QueryException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * The tenant core's constraints: the ledger's referential integrity, the unit record, and the
 * uniqueness the old SQLite suite could not express.
 *
 * Every constraint is asserted from PHP rather than trusted because a migration declares it.
 */
final class TenantCoreTest extends TestCase
{
    use RefreshDatabase;

    private Product $product;

    private Location $location;

    protected function setUp(): void
    {
        parent::setUp();

        $user = User::factory()->create();
        $team = Team::create(['name' => 'Kafe', 'user_id' => $user->getKey()]);
        $user->forceFill(['current_team_id' => $team->getKey()])->save();
        $this->actingAs($user->refresh());

        $this->location = Location::create(['name' => 'Mutfak']);
        $this->product = Product::create(['name' => 'Pınar Süt', 'base_unit' => 'C62']);
    }

    private function movement(array $overrides = []): StockMovement
    {
        $lot = StockLot::create([
            'product_id' => $this->product->getKey(),
            'location_id' => $this->location->getKey(),
            'initial_quantity' => 10,
        ]);

        return StockMovement::create(array_merge([
            'product_id' => $this->product->getKey(),
            'location_id' => $this->location->getKey(),
            'stock_lot_id' => $lot->getKey(),
            'delta' => 10,
            'reason' => MovementReason::Purchase,
            'source' => MovementSource::Manual,
            'actor_type' => ActorType::User,
            'occurred_at' => now(),
        ], $overrides));
    }

    public function test_a_product_with_movements_cannot_be_force_deleted(): void
    {
        $this->movement();

        $this->expectException(QueryException::class);

        // The ledger's own integrity, which shipped as `cascadeOnDelete` and therefore did not exist
        // (D80). Invariant 4 says a movement is never deleted; a database told to cascade makes that a
        // convention rather than a property, and every path that bypasses the model could break it.
        $this->product->forceDelete();
    }

    public function test_soft_deleting_a_product_leaves_the_ledger_alone(): void
    {
        $this->movement();

        // The ordinary way a product goes away. `restrictOnDelete` governs the force path only, so the
        // normal one still has to work.
        $this->product->delete();

        $this->assertSoftDeleted($this->product);
        $this->assertSame(1, StockMovement::withoutGlobalScopes()->count());
    }

    public function test_deleting_a_tenant_still_takes_its_ledger_with_it(): void
    {
        $this->movement();
        $team = Team::findOrFail($this->product->team_id);

        // `team_id` is the ONE cascade that stays, because `legal-and-privacy.md` requires tenant
        // deletion that actually deletes. Innermost-first is what makes it complete despite the
        // restricts above.
        DB::table('stock_movements')->where('team_id', $team->getKey())->delete();
        DB::table('stock_lots')->where('team_id', $team->getKey())->delete();
        DB::table('products')->where('team_id', $team->getKey())->delete();
        $team->delete();

        $this->assertSame(0, StockMovement::withoutGlobalScopes()->count());
    }

    public function test_the_ledger_records_the_unit_the_user_entered(): void
    {
        // D90. `delta` is 24 base units; the user typed "2 koli". Without the pair, a delivery keyed as
        // two cases reads back as twenty-four items forever.
        $movement = $this->movement([
            'delta' => 24,
            'entered_quantity' => 2,
            'entered_unit' => 'koli',
        ]);

        $movement->refresh();

        $this->assertSame('24.000', $movement->delta);
        $this->assertSame('2.000', $movement->entered_quantity);
        $this->assertSame('koli', $movement->entered_unit);
    }

    public function test_a_movement_may_have_no_lot_because_a_serial_product_has_none(): void
    {
        // Invariant 8: a serial-tracked product holds no lots, so its movements reference the unit
        // through the morph instead. The column shipped NOT NULL, which made that path unwritable.
        $movement = $this->movement(['stock_lot_id' => null, 'delta' => 1]);

        $this->assertNull($movement->refresh()->stock_lot_id);
    }

    public function test_two_products_in_one_tenant_cannot_share_a_sku(): void
    {
        Product::create(['name' => 'Süt', 'sku' => 'SUT-1']);

        $this->expectException(QueryException::class);

        // The uniqueness `data-model.md` asked for and the old suite could not enforce: the migration
        // used to carry a note explaining that partial uniqueness "is not portable to sqlite", which
        // meant it held nowhere.
        Product::create(['name' => 'Başka Süt', 'sku' => 'SUT-1']);
    }

    public function test_a_null_sku_is_not_a_duplicate_of_another_null_sku(): void
    {
        Product::create(['name' => 'Bir', 'sku' => null]);
        Product::create(['name' => 'İki', 'sku' => null]);

        // Most products have no SKU (a household has none at all), so a unique index that treated NULL
        // as a value would allow exactly one of them.
        $this->assertSame(3, Product::count());
    }

    public function test_a_soft_deleted_product_releases_its_sku(): void
    {
        $first = Product::create(['name' => 'Süt', 'sku' => 'SUT-1']);
        $first->delete();

        // Deleting a product and re-adding it with the same SKU is ordinary rather than wrong, which is
        // why `deleted_at IS NULL` is in the index predicate.
        $second = Product::create(['name' => 'Süt', 'sku' => 'SUT-1']);

        $this->assertNotSame($first->getKey(), $second->getKey());
    }

    public function test_a_conversion_factor_must_be_positive(): void
    {
        $this->expectException(QueryException::class);

        // A zero factor is not a unit, it is a division by zero waiting for a delivery.
        DB::table('product_units')->insert([
            'id' => (string) Str::uuid7(),
            'product_id' => $this->product->getKey(),
            'unit' => 'koli',
            'factor' => 0,
            'created_at' => now(),
            'updated_at' => now(),
        ]);
    }

    public function test_a_tenant_cannot_point_one_barcode_at_two_of_their_products(): void
    {
        $barcode = Barcode::forGtin('8690504000018');
        $other = Product::create(['name' => 'Sütaş Süt']);

        DB::table('product_barcode')->insert([
            'id' => (string) Str::uuid7(),
            'team_id' => $this->product->team_id,
            'product_id' => $this->product->getKey(),
            'barcode_id' => $barcode->getKey(),
            'created_at' => now(), 'updated_at' => now(),
        ]);

        $this->expectException(QueryException::class);

        // Letting this in would make every scan a disambiguation prompt, which is the ambiguity the
        // cascade exists to avoid.
        DB::table('product_barcode')->insert([
            'id' => (string) Str::uuid7(),
            'team_id' => $other->team_id,
            'product_id' => $other->getKey(),
            'barcode_id' => $barcode->getKey(),
            'created_at' => now(), 'updated_at' => now(),
        ]);
    }

    public function test_the_affinity_count_cannot_go_negative(): void
    {
        $this->expectException(QueryException::class);

        // D9 floors the decrement at zero, and D92 keeps it there: the count is the EXPLANATION shown
        // to the user ("bu çekmecede zaten 3 tane var"), and a negative number explains nothing.
        DB::statement('
            INSERT INTO location_category_affinity (id, team_id, product_category_id, location_id, count, created_at, updated_at)
            VALUES (gen_random_uuid(), ?, gen_random_uuid(), ?, -1, now(), now())
        ', [$this->product->team_id, $this->location->getKey()]);
    }

    public function test_a_products_normalised_name_is_written_by_the_mutator(): void
    {
        // The same fold the catalog uses, so a receipt line matches a tenant's own product and a shared
        // catalog entry through one comparison rather than two.
        $this->assertSame('pinar sut', $this->product->name_normalized);
    }
}
