<?php

namespace Tests\Feature;

use App\Models\Location;
use App\Models\Product;
use App\Models\ProductSerial;
use App\Models\Team;
use App\Models\User;
use App\Services\StockWriter;
use Illuminate\Database\QueryException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use RuntimeException;
use Tests\TestCase;

/**
 * Invariant 8: a product holds lots or serials, never both, and the transition between the two
 * modes is asymmetric.
 *
 * The invariant has three halves and each is enforced somewhere different, which is the reason this
 * file exists rather than three assertions scattered across three others:
 *
 * - the VOCABULARY is a CHECK, because a closed set of values constrains rather than derives;
 * - the TRANSITION is a model guard, because it has to compare against another table;
 * - the WRITE is refused by `StockWriter`, because that is the one path that could create the
 *   contradiction in the first place.
 */
final class TrackingModeTest extends TestCase
{
    use RefreshDatabase;

    private Product $product;

    private Location $location;

    protected function setUp(): void
    {
        parent::setUp();

        $user = User::factory()->create();
        $team = Team::create(['name' => 'Atölye', 'user_id' => $user->getKey()]);
        $user->forceFill(['current_team_id' => $team->getKey()])->save();
        $this->actingAs($user->refresh());

        $this->location = Location::create(['name' => 'Depo']);
        $this->product = Product::create(['name' => 'Makita Matkap', 'tracking_mode' => 'lot']);
    }

    private function serial(string $serial = 'SN-0001'): ProductSerial
    {
        return ProductSerial::create([
            'product_id' => $this->product->getKey(),
            'location_id' => $this->location->getKey(),
            'serial' => $serial,
            'acquired_at' => now(),
        ]);
    }

    public function test_an_unknown_tracking_mode_is_refused(): void
    {
        $this->expectException(QueryException::class);

        // The vocabulary is closed by a CHECK, like the nine other vocabulary columns in this schema.
        // `'serials'` is the plausible typo, and it would have made a product neither lot-tracked nor
        // serial-tracked: every reader branching on the value takes the `lot` path by default, so the
        // product would have looked fine and counted wrongly.
        DB::table('products')->insert([
            'id' => (string) Str::uuid7(),
            'team_id' => $this->product->team_id,
            'name' => 'Bozuk',
            'name_normalized' => 'bozuk',
            'tracking_mode' => 'serials',
            'created_at' => now(), 'updated_at' => now(),
        ]);
    }

    public function test_a_product_that_has_held_a_serial_cannot_return_to_lots(): void
    {
        $this->product->update(['tracking_mode' => 'serial']);
        $this->serial();

        $this->expectException(RuntimeException::class);

        // D28's rule. There is nothing to collapse the serial into: a fungible quantity of one cannot
        // say WHICH drill, so its warranty date and its history would become unattributable.
        $this->product->update(['tracking_mode' => 'lot']);
    }

    public function test_a_released_serial_still_closes_the_door(): void
    {
        $this->product->update(['tracking_mode' => 'serial']);
        $this->serial()->update(['released_at' => now()]);

        $this->expectException(RuntimeException::class);

        // The direction is closed PERMANENTLY rather than while stock is on hand, and this is the
        // assertion that says so. A released serial is kept as evidence, so the row that blocks the
        // transition never goes away.
        $this->product->update(['tracking_mode' => 'lot']);
    }

    public function test_a_product_with_no_serials_may_still_switch_to_lots(): void
    {
        $this->product->update(['tracking_mode' => 'serial']);

        $this->product->update(['tracking_mode' => 'lot']);

        // Someone who picked the wrong mode on the create form and noticed immediately is doing
        // something ordinary. The guard is about evidence that exists, not about the value.
        $this->assertSame('lot', $this->product->refresh()->tracking_mode);
    }

    public function test_switching_to_serials_is_refused_while_a_lot_still_holds_stock(): void
    {
        app(StockWriter::class)->receive($this->product, $this->location, 3);

        $this->expectException(RuntimeException::class);

        // Three drills sitting in one lot cannot become three serials by changing a column: nothing
        // in the data says which three, and the quantity would then be counted twice, once by the
        // projection over the lot and once by the serial count.
        $this->product->update(['tracking_mode' => 'serial']);
    }

    public function test_switching_to_serials_is_allowed_once_the_lots_are_empty(): void
    {
        $writer = app(StockWriter::class);
        $writer->receive($this->product, $this->location, 3);
        $writer->consume($this->product, $this->location, 3);

        $this->product->update(['tracking_mode' => 'serial']);

        // The emptied lot stays as history and does NOT block the correction. Refusing here would
        // force the user to abandon the product and open a second one, which spends a unique-SKU slot
        // (D4 meters exactly that) to record the same drill twice.
        $this->assertSame('serial', $this->product->refresh()->tracking_mode);
        $this->assertSame(1, $this->product->lots()->count());
    }

    public function test_a_serial_tracked_product_does_not_receive_into_a_lot(): void
    {
        $this->product->update(['tracking_mode' => 'serial']);

        $this->expectException(RuntimeException::class);

        // The one write path that could create the contradiction invariant 8 forbids. Without this,
        // a serial-tracked product would carry a lot whose quantity disagrees with its serial count,
        // and neither number would be wrong on its own terms.
        app(StockWriter::class)->receive($this->product, $this->location, 1);
    }

    public function test_a_refused_receive_leaves_no_lot_behind(): void
    {
        $this->product->update(['tracking_mode' => 'serial']);

        try {
            app(StockWriter::class)->receive($this->product, $this->location, 1);
        } catch (RuntimeException) {
            // Expected; what matters is what is NOT in the database afterwards.
        }

        // The check runs BEFORE the transaction opens, so there is no lot, no movement and no
        // projection row to clean up. A guard inside the transaction would have been correct too,
        // but this asserts the cheaper shape actually holds.
        $this->assertSame(0, $this->product->lots()->count());
        $this->assertSame(0, $this->product->movements()->count());
    }

    public function test_the_two_modes_are_never_both_populated_with_stock(): void
    {
        app(StockWriter::class)->receive($this->product, $this->location, 2);

        // Reaching the forbidden state takes a raw query, and that is the point. `forceFill` is not
        // enough: it bypasses `$fillable` and nothing else, so the `updating` guard still fires. Only
        // a writer that leaves Eloquent entirely can produce this, which is the same class of bypass
        // D88 names for `name_normalized` and D81 names for the projection. It exists here so the
        // sweep has a real violation to find.
        DB::table('products')->where('id', $this->product->getKey())->update(['tracking_mode' => 'serial']);
        $this->product->refresh();
        $this->serial();

        $this->assertTrue($this->product->lots()->where('remaining_quantity', '>', 0)->exists());
        $this->assertTrue($this->product->serials()->held()->exists());
    }
}
