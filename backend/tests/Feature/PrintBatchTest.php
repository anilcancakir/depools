<?php

namespace Tests\Feature;

use App\Models\Location;
use App\Models\Product;
use App\Models\Team;
use App\Models\User;
use Illuminate\Database\QueryException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * Print batches: the two label regimes D45 settled, and the paper accounting D43 asked for.
 */
final class PrintBatchTest extends TestCase
{
    use RefreshDatabase;

    private string $teamId;

    private string $batchId;

    private Product $product;

    protected function setUp(): void
    {
        parent::setUp();

        $user = User::factory()->create();
        $team = Team::create(['name' => 'Atölye', 'user_id' => $user->getKey()]);
        $user->forceFill(['current_team_id' => $team->getKey()])->save();
        $this->actingAs($user->refresh());

        $this->teamId = $team->getKey();
        $this->product = Product::create(['name' => 'Braket M8']);
        $this->batchId = (string) Str::uuid7();

        DB::table('print_batches')->insert([
            'id' => $this->batchId,
            'team_id' => $this->teamId,
            'template' => 'a4_8_up_105x70',
            'created_at' => now(), 'updated_at' => now(),
        ]);
    }

    private function serial(string $serial = 'SN-0001'): string
    {
        $id = (string) Str::uuid7();
        $location = Location::create(['name' => 'Raf 3']);

        DB::table('product_serials')->insert([
            'id' => $id,
            'team_id' => $this->teamId,
            'product_id' => $this->product->getKey(),
            'location_id' => $location->getKey(),
            'serial' => $serial,
            'acquired_at' => now(),
            'created_at' => now(), 'updated_at' => now(),
        ]);

        return $id;
    }

    /** @param array<string, mixed> $attributes */
    private function item(array $attributes = []): void
    {
        DB::table('print_batch_items')->insert(array_merge([
            'id' => (string) Str::uuid7(),
            'team_id' => $this->teamId,
            'print_batch_id' => $this->batchId,
            'product_id' => $this->product->getKey(),
            'copies' => 12,
            'position' => 1,
            'print_count' => 0,
            'created_at' => now(), 'updated_at' => now(),
        ], $attributes));
    }

    public function test_a_product_line_may_ask_for_many_copies(): void
    {
        // A lot-tracked product's label identifies the PRODUCT, so twelve stickers are twelve copies of
        // one design and the count is free.
        $this->item(['copies' => 12]);

        $this->assertSame(12, DB::table('print_batch_items')->first()->copies);
    }

    public function test_a_serial_line_prints_exactly_once(): void
    {
        $this->expectException(QueryException::class);

        // D45's absent stepper, in the schema. A serial's label is one specific sticker, so asking for
        // three is asking for three of a unit that exists once. The UI omits the control; this makes the
        // rule impossible to reintroduce by accident.
        $this->item(['product_id' => null, 'product_serial_id' => $this->serial(), 'copies' => 3]);
    }

    public function test_a_serial_line_with_one_copy_is_fine(): void
    {
        $this->item(['product_id' => null, 'product_serial_id' => $this->serial(), 'copies' => 1]);

        $this->assertNotNull(DB::table('print_batch_items')->first()->product_serial_id);
    }

    public function test_a_line_cannot_name_both_a_product_and_a_serial(): void
    {
        $this->expectException(QueryException::class);

        // Two subjects is not a label, it is an ambiguity about what gets printed.
        $this->item(['product_serial_id' => $this->serial()]);
    }

    public function test_a_line_must_name_something(): void
    {
        $this->expectException(QueryException::class);

        $this->item(['product_id' => null, 'product_serial_id' => null]);
    }

    public function test_an_unprinted_line_carries_no_print_count(): void
    {
        $this->expectException(QueryException::class);

        // Otherwise the resume query (`printed_at IS NULL`) and the paper count can disagree, and D43
        // takes paper seriously enough that the two must not.
        $this->item(['printed_at' => null, 'print_count' => 2]);
    }

    public function test_a_reprint_is_counted_rather_than_only_re_dated(): void
    {
        $this->item();

        // First print.
        DB::table('print_batch_items')->update(['printed_at' => now(), 'print_count' => 1]);
        // The printer jams and the user reprints the range.
        DB::table('print_batch_items')->update(['printed_at' => now(), 'print_count' => 2]);

        // Two runs means two sheets of stickers. `printed_at` alone would have said "printed" and lost
        // the second sheet, so "why did three sheets go" would have no answer in the data (D104).
        $this->assertSame(2, DB::table('print_batch_items')->first()->print_count);
    }

    public function test_a_partially_printed_batch_names_what_is_left(): void
    {
        $this->item(['position' => 1, 'printed_at' => now(), 'print_count' => 1]);
        $this->item(['position' => 2]);
        $this->item(['position' => 3]);

        // The resume query `labeling-and-printing.md` asks for, in sheet order.
        $remaining = DB::table('print_batch_items')
            ->where('print_batch_id', $this->batchId)
            ->whereNull('printed_at')
            ->orderBy('position')
            ->pluck('position')
            ->all();

        $this->assertSame([2, 3], $remaining);
    }

    public function test_two_lines_cannot_hold_the_same_sheet_position(): void
    {
        $this->item(['position' => 1]);

        $this->expectException(QueryException::class);

        // Position is what lets a jammed print name a range, so two lines sharing one makes the range
        // ambiguous.
        $this->item(['position' => 1]);
    }
}
