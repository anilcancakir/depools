<?php

namespace Tests\Feature;

use App\Models\Barcode;
use App\Models\PrintBatch;
use App\Models\PrintBatchItem;
use App\Models\Product;
use App\Models\ProductSerial;
use App\Models\Team;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Storage;
use InvalidArgumentException;
use Symfony\Component\Process\Process;
use Tests\Concerns\NeedsRenderToolchain;
use Tests\TestCase;

/**
 * Print batches over HTTP: accumulating lines, printing some of them, and resuming.
 *
 * The criterion this exists for is number 5, that a partially printed batch is resumable.
 *
 * **`PrintBatchTest` is the other half and it is not redundant.** That file drives the CONSTRAINTS with
 * raw inserts, so the CHECKs on `print_batch_items` stay guarded whatever the models do; this one
 * drives the endpoints and the model behaviour on top of them. It exists because I overwrote that file
 * with this one without reading it, which cost two assertions nothing here replaces: the
 * `printed_at`/`print_count` agreement, and `unique(print_batch_id, position)`.
 */
final class PrintBatchApiTest extends TestCase
{
    use NeedsRenderToolchain;
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();

        // An empty render cache per test, so one test's sheet cannot answer another's assertion.
        Storage::fake('local');
    }

    public function test_a_batch_from_another_team_is_not_found_rather_than_refused(): void
    {
        $alpha = $this->tenant('Alpha');

        $this->tenant('Beta');
        $theirs = $this->batch([['product_id' => $this->product('Someone Else Milk')->getKey()]]);

        $this->actingAs($alpha, 'sanctum');

        $this->getJson("/api/v1/labels/batches/{$theirs->getKey()}")->assertNotFound();
        $this->postJson("/api/v1/labels/batches/{$theirs->getKey()}/settle")->assertNotFound();
        $this->postJson("/api/v1/labels/batches/{$theirs->getKey()}/pdf")->assertNotFound();
        $this->postJson("/api/v1/labels/batches/{$theirs->getKey()}/lines", [
            'items' => [['product_id' => $this->product('Mine')->getKey()]],
        ])->assertNotFound();
    }

    public function test_a_product_from_another_team_cannot_be_added_to_my_batch(): void
    {
        $alpha = $this->tenant('Alpha');
        $batch = $this->batch();

        $this->tenant('Beta');
        $theirs = $this->product('Someone Else Milk');

        $this->actingAs($alpha, 'sanctum');

        // The foreign key would refuse it too, but as a 500 naming a constraint. `TeamScope` makes the
        // lookup find nothing, which is the 404 `backend.md` requires of a cross-tenant read.
        $this->postJson("/api/v1/labels/batches/{$batch->getKey()}/lines", [
            'items' => [['product_id' => $theirs->getKey()]],
        ])->assertNotFound();

        $this->assertSame(0, $batch->items()->count());
    }

    public function test_the_endpoints_are_behind_authentication(): void
    {
        $this->getJson('/api/v1/labels/batches')->assertUnauthorized();
        $this->postJson('/api/v1/labels/batches', [])->assertUnauthorized();
    }

    public function test_a_batch_accumulates_lines_and_keeps_their_order(): void
    {
        $this->tenant();

        $first = $this->product('Pınar Süt Tam Yağlı 1 lt');
        $second = $this->product('Şeker (Toz) 1 kg');

        $created = $this->postJson('/api/v1/labels/batches', [
            'name' => 'Salı teslimi',
            'template' => 'a4_24_up_70x37',
            'items' => [['product_id' => $first->getKey(), 'copies' => 12]],
        ])->assertCreated();

        $id = $created->json('data.id');

        $this->postJson("/api/v1/labels/batches/{$id}/lines", [
            'items' => [['product_id' => $second->getKey(), 'copies' => 3]],
        ])->assertOk();

        $response = $this->getJson("/api/v1/labels/batches/{$id}")->assertOk();

        // Positions are what a person reprinting names, so they continue rather than restart: a second
        // add that began at 1 again would make "reprint 12 to 24" ambiguous forever.
        $this->assertSame([1, 2], array_column($response->json('data.items'), 'position'));
        $this->assertSame(15, $response->json('data.sticker_count'));
        $this->assertSame(15, $response->json('data.pending_sticker_count'));
    }

    public function test_a_serial_line_prints_once_and_carries_no_stepper(): void
    {
        $this->tenant();

        $product = $this->product('Makita DHP484 Darbeli Matkap');
        $serial = $this->serial($product, 'MK-0001');

        $created = $this->postJson('/api/v1/labels/batches', [
            'template' => 'a4_24_up_70x37',
            // 5 copies asked for. D45 says a serial's label identifies one physical unit, so there is
            // nothing to multiply, and the request's number is ignored rather than refused.
            'items' => [['product_serial_id' => $serial->getKey(), 'copies' => 5]],
        ])->assertCreated();

        $item = $created->json('data.items.0');

        $this->assertSame('per_serial', $item['mode']);
        $this->assertSame(1, $item['count']);
        $this->assertSame('MK-0001', $item['serial']);
        $this->assertSame(1, $created->json('data.sticker_count'));
    }

    public function test_a_line_with_both_subjects_or_neither_is_refused(): void
    {
        $this->tenant();

        $product = $this->product('Tornavida Seti PH2');
        $serial = $this->serial($product, 'TS-0001');

        $this->postJson('/api/v1/labels/batches', [
            'template' => 'a4_24_up_70x37',
            'items' => [['product_id' => $product->getKey(), 'product_serial_id' => $serial->getKey()]],
        ])->assertUnprocessable();

        $this->postJson('/api/v1/labels/batches', [
            'template' => 'a4_24_up_70x37',
            'items' => [['copies' => 2]],
        ])->assertUnprocessable();
    }

    public function test_the_model_names_the_mistake_the_database_cannot_explain(): void
    {
        $this->tenant();
        $batch = $this->batch();

        $this->expectException(InvalidArgumentException::class);

        // `print_batch_items_one_subject_per_row` covers both "neither" and "both", so its SQLSTATE
        // cannot tell a caller which one they did. The model's own guard can.
        $item = new PrintBatchItem;
        $item->setAttribute('team_id', $batch->team_id);
        $item->fill(['print_batch_id' => $batch->getKey(), 'copies' => 1, 'position' => 1]);
        $item->save();
    }

    public function test_a_partially_printed_batch_is_resumable(): void
    {
        $this->tenant();

        $batch = $this->batch([
            ['product_id' => $this->product('One')->getKey()],
            ['product_id' => $this->product('Two')->getKey()],
            ['product_id' => $this->product('Three')->getKey()],
        ]);

        // The printer jammed after the first two.
        $response = $this->postJson("/api/v1/labels/batches/{$batch->getKey()}/settle", [
            'positions' => [1, 2],
        ])->assertOk();

        $this->assertSame(2, $response->json('meta.marked'));
        $this->assertSame(1, $response->json('data.pending_sticker_count'));
        $this->assertSame(3, $response->json('data.sticker_count'));

        // Criterion 5: the batch is not finished, and what it still owes is exactly the third line.
        $this->assertNull($response->json('data.printed_at'));
        $this->assertTrue($batch->fresh()->isUnfinished());

        $pending = array_values(array_filter(
            $response->json('data.items'),
            static fn (array $item): bool => $item['is_printed'] === false,
        ));

        $this->assertCount(1, $pending);
        $this->assertSame(3, $pending[0]['position']);
    }

    public function test_a_batch_closes_only_when_nothing_is_left(): void
    {
        $this->tenant();

        $batch = $this->batch([
            ['product_id' => $this->product('One')->getKey()],
            ['product_id' => $this->product('Two')->getKey()],
        ]);

        $this->postJson("/api/v1/labels/batches/{$batch->getKey()}/settle", ['positions' => [1]])
            ->assertOk()
            ->assertJsonPath('data.printed_at', null);

        // **Derived, never authored.** `printed_at` on the batch is read from the items after the write,
        // so a batch printed in two passes closes on the second without anybody saying so.
        $this->postJson("/api/v1/labels/batches/{$batch->getKey()}/settle", ['positions' => [2]])
            ->assertOk();

        $this->assertNotNull($batch->fresh()->printed_at);
        $this->assertFalse($batch->fresh()->isUnfinished());
    }

    public function test_settling_the_sheet_twice_does_not_count_paper_that_did_not_go(): void
    {
        $this->tenant();

        $batch = $this->batch([['product_id' => $this->product('One')->getKey()]]);

        $this->postJson("/api/v1/labels/batches/{$batch->getKey()}/settle")->assertOk();
        $response = $this->postJson("/api/v1/labels/batches/{$batch->getKey()}/settle")->assertOk();

        // **Settling with no positions means "what the sheet held", which is the PENDING lines.** The
        // render sends those and the screen settles with no positions, so an unfiltered mark hit the
        // already-printed rows too: a second `print_count` for stickers that never came off a printer,
        // and a fresh `printed_at` over the timestamp of the pass that did.
        //
        // This test used to assert the opposite, on the reading that "a label printed twice is two
        // stickers". That is true, and naming the position is how a caller says it: see below.
        $this->assertSame(0, $response->json('meta.marked'));
        $this->assertSame(1, $response->json('data.items.0.print_count'));
        $this->assertTrue($response->json('data.items.0.is_printed'));
    }

    public function test_naming_a_printed_position_reprints_it_and_counts_the_second_sticker(): void
    {
        $this->tenant();

        $batch = $this->batch([['product_id' => $this->product('One')->getKey()]]);

        $this->postJson("/api/v1/labels/batches/{$batch->getKey()}/settle")->assertOk();

        // A reprint is deliberate and explicit: the caller names the row. Two runs means two sheets of
        // stickers, and D43 takes paper seriously enough that the count has to say so.
        $response = $this->postJson("/api/v1/labels/batches/{$batch->getKey()}/settle", [
            'positions' => [1],
        ])->assertOk();

        $this->assertSame(1, $response->json('meta.marked'));
        $this->assertSame(2, $response->json('data.items.0.print_count'));
    }

    public function test_a_second_pass_leaves_the_first_passs_record_alone(): void
    {
        $this->tenant();

        $batch = $this->batch([
            ['product_id' => $this->product('One')->getKey()],
            ['product_id' => $this->product('Two')->getKey()],
        ]);

        $this->postJson("/api/v1/labels/batches/{$batch->getKey()}/settle", ['positions' => [1]])
            ->assertOk();

        $first = $batch->fresh()->items()->where('position', 1)->sole();
        $printedAt = $first->printed_at;

        // The jam is fixed and the remaining sheet goes through. The line that already printed keeps its
        // count AND its timestamp: without the pending filter this pass rewrote both.
        $this->postJson("/api/v1/labels/batches/{$batch->getKey()}/settle")->assertOk();

        $again = $batch->fresh()->items()->where('position', 1)->sole();

        $this->assertSame(1, $again->print_count);
        $this->assertTrue($printedAt->equalTo($again->printed_at));
        $this->assertNotNull($batch->fresh()->printed_at);
    }

    public function test_settling_a_position_this_batch_does_not_have_is_refused(): void
    {
        $this->tenant();

        $batch = $this->batch([['product_id' => $this->product('One')->getKey()]]);

        // Silently marking the ones that do exist would leave a client believing the rest printed too,
        // which on this feature means throwing away sheets that were fine.
        $this->postJson("/api/v1/labels/batches/{$batch->getKey()}/settle", ['positions' => [1, 9]])
            ->assertUnprocessable()
            ->assertJsonValidationErrors('positions');

        $this->assertTrue($batch->fresh()->items()->first()->isUnprinted());
    }

    public function test_the_pdf_renders_only_what_the_batch_still_owes(): void
    {
        $this->tenant();
        $this->requireRenderToolchain();

        $batch = $this->batch([
            ['product_id' => $this->product('PRINTED ALREADY')->getKey()],
            ['product_id' => $this->product('STILL PENDING')->getKey()],
        ], 'a4_8_up_105x70');

        $this->postJson("/api/v1/labels/batches/{$batch->getKey()}/settle", ['positions' => [1]])
            ->assertOk();

        $this->postJson("/api/v1/labels/batches/{$batch->getKey()}/pdf")->assertOk();

        $text = $this->extract(
            Storage::disk('local')->get(Storage::disk('local')->files('label-sheets')[0])
        );

        // Rendering the whole batch would reprint stickers that already came out, and paper is what
        // this feature is judged on.
        $this->assertStringContainsString('STILL PENDING', $text);
        $this->assertStringNotContainsString('PRINTED ALREADY', $text);
    }

    public function test_a_finished_batch_has_nothing_to_print(): void
    {
        $this->tenant();

        $batch = $this->batch([['product_id' => $this->product('One')->getKey()]]);

        $this->postJson("/api/v1/labels/batches/{$batch->getKey()}/settle")->assertOk();

        $this->postJson("/api/v1/labels/batches/{$batch->getKey()}/pdf")
            ->assertUnprocessable()
            ->assertJsonValidationErrors('batch');
    }

    public function test_rendering_does_not_mark_anything_printed(): void
    {
        $this->tenant();
        $this->requireRenderToolchain();

        $batch = $this->batch([['product_id' => $this->product('One')->getKey()]], 'a4_8_up_105x70');

        $this->postJson("/api/v1/labels/batches/{$batch->getKey()}/pdf")->assertOk();

        // The server cannot know whether the file reached a printer, so the client reports it. A render
        // that marked would make a cancelled print dialog look like a finished batch.
        $this->assertTrue($batch->fresh()->items()->first()->isUnprinted());
        $this->assertNull($batch->fresh()->printed_at);
    }

    public function test_the_list_puts_unfinished_batches_first(): void
    {
        $this->tenant();

        $finished = $this->batch([['product_id' => $this->product('Old')->getKey()]]);
        $this->postJson("/api/v1/labels/batches/{$finished->getKey()}/settle")->assertOk();

        $open = $this->batch([['product_id' => $this->product('New')->getKey()]]);

        $ids = array_column($this->getJson('/api/v1/labels/batches')->assertOk()->json('data'), 'id');

        // A resumable batch is the reason a user opens this list; a finished one is history.
        $this->assertSame([$open->getKey(), $finished->getKey()], $ids);
    }

    public function test_a_line_can_change_its_copies_and_be_dropped(): void
    {
        $this->tenant();

        $batch = $this->batch([
            ['product_id' => $this->product('One')->getKey(), 'copies' => 2],
            ['product_id' => $this->product('Two')->getKey()],
        ]);

        $this->putJson("/api/v1/labels/batches/{$batch->getKey()}/lines/1", ['copies' => 9])
            ->assertOk()
            ->assertJsonPath('data.items.0.count', 9);

        $response = $this->deleteJson("/api/v1/labels/batches/{$batch->getKey()}/lines/2")->assertOk();

        // **Positions are not renumbered.** They are what a person reprinting names, so closing the gap
        // would renumber lines a half-printed sheet already identified.
        $this->assertSame([1], array_column($response->json('data.items'), 'position'));
        $this->assertSame(9, $response->json('data.sticker_count'));
    }

    public function test_a_printed_line_keeps_its_count_and_stays(): void
    {
        $this->tenant();

        $batch = $this->batch([['product_id' => $this->product('One')->getKey(), 'copies' => 4]]);

        $this->postJson("/api/v1/labels/batches/{$batch->getKey()}/settle")->assertOk();

        // A printed line records that stickers exist. Changing its count would make the paper
        // arithmetic disagree with the sheets that came out, and removing it would claim fewer labels
        // printed than did.
        $this->putJson("/api/v1/labels/batches/{$batch->getKey()}/lines/1", ['copies' => 1])
            ->assertUnprocessable()
            ->assertJsonValidationErrors('copies');

        $this->deleteJson("/api/v1/labels/batches/{$batch->getKey()}/lines/1")
            ->assertUnprocessable()
            ->assertJsonValidationErrors('position');

        $this->assertSame(4, $batch->fresh()->items()->first()->copies);
    }

    public function test_a_serial_line_has_no_copies_to_change(): void
    {
        $this->tenant();

        $product = $this->product('Makita DHP484 Darbeli Matkap');
        $serial = $this->serial($product, 'MK-0003');

        $batch = $this->batch([['product_serial_id' => $serial->getKey()]]);

        // D45's absent stepper, at the boundary: the CHECK would refuse it too, but as a 500.
        $this->putJson("/api/v1/labels/batches/{$batch->getKey()}/lines/1", ['copies' => 3])
            ->assertUnprocessable()
            ->assertJsonValidationErrors('copies');
    }

    public function test_a_line_of_another_teams_batch_cannot_be_touched(): void
    {
        $alpha = $this->tenant('Alpha');

        $this->tenant('Beta');
        $theirs = $this->batch([['product_id' => $this->product('Theirs')->getKey()]]);

        $this->actingAs($alpha, 'sanctum');

        $this->putJson("/api/v1/labels/batches/{$theirs->getKey()}/lines/1", ['copies' => 2])
            ->assertNotFound();
        $this->deleteJson("/api/v1/labels/batches/{$theirs->getKey()}/lines/1")->assertNotFound();
    }

    public function test_the_wire_carries_the_code_each_line_will_print(): void
    {
        $this->tenant();

        $withGtin = $this->product('Pınar Süt Tam Yağlı 1 lt');
        $withGtin->linkBarcode(Barcode::forGtin('8690504004073'));

        $bare = $this->product('Kablo bağı 200 mm');

        $serialised = $this->product('Makita DHP484 Darbeli Matkap');
        $serial = $this->serial($serialised, 'MK-0009');

        $batch = $this->batch([
            ['product_id' => $withGtin->getKey()],
            ['product_id' => $bare->getKey()],
            ['product_serial_id' => $serial->getKey()],
        ]);

        $items = $this->getJson("/api/v1/labels/batches/{$batch->getKey()}")->assertOk()->json('data.items');

        // **This field was missing entirely and three consumers ran on a placeholder**: the sample label
        // the copy calls "real content", the fit verdict `max_code_length` exists for, and the row meta
        // that told users a code would be generated for products carrying a real barcode.
        //
        // A GTIN prints its significant digits, a product with nothing gets the generated form, and a
        // serial's label identifies one unit so the serial IS the code.
        $this->assertSame('8690504004073', $items[0]['code']);
        $this->assertMatchesRegularExpression('/^DPL[0-9A-F]{8}$/', $items[1]['code']);
        $this->assertSame('MK-0009', $items[2]['code']);
    }

    public function test_appending_to_a_printed_batch_is_refused(): void
    {
        $this->tenant();

        $batch = $this->batch([['product_id' => $this->product('One')->getKey()]]);

        $this->postJson("/api/v1/labels/batches/{$batch->getKey()}/settle")->assertOk();
        $this->assertNotNull($batch->fresh()->printed_at);

        // `printed_at` is DERIVED, so an insert breaks it without touching the column: the batch would
        // carry a finished date over pending lines. `update()` already refused the same thing.
        $this->postJson("/api/v1/labels/batches/{$batch->getKey()}/lines", [
            'items' => [['product_id' => $this->product('Two')->getKey()]],
        ])->assertUnprocessable()->assertJsonValidationErrors('items');

        $this->assertSame(1, $batch->fresh()->items()->count());
    }

    public function test_a_non_numeric_position_is_not_found_rather_than_a_server_error(): void
    {
        $this->tenant();

        $batch = $this->batch([['product_id' => $this->product('One')->getKey()]]);

        // The handlers type `{position}` as `int` and there is no `declare(strict_types=1)`, so without
        // a route constraint a non-numeric segment is a `TypeError` and a 500.
        $this->putJson("/api/v1/labels/batches/{$batch->getKey()}/lines/abc", ['copies' => 2])
            ->assertNotFound();
        $this->deleteJson("/api/v1/labels/batches/{$batch->getKey()}/lines/abc")->assertNotFound();
    }

    /**
     * @param  list<array<string, mixed>>  $items
     */
    private function batch(array $items = [], string $template = 'a4_24_up_70x37'): PrintBatch
    {
        $batch = PrintBatch::create(['template' => $template, 'fields' => ['name', 'code']]);

        $position = 1;

        foreach ($items as $item) {
            $batch->items()->create([
                ...$item,
                'copies' => $item['copies'] ?? 1,
                'position' => $position++,
            ]);
        }

        return $batch->refresh();
    }

    private function extract(string $pdf): string
    {
        $path = tempnam(sys_get_temp_dir(), 'label').'.pdf';
        file_put_contents($path, $pdf);

        $process = new Process(['pdftotext', '-layout', $path, '-']);
        $process->run();

        unlink($path);

        return $process->getOutput();
    }

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
        return Product::create(['name' => $name, 'base_unit' => 'C62']);
    }

    /**
     * One tracked unit.
     *
     * `acquired_at` is NOT NULL on `product_serials`, which is right: a unit the business holds was
     * acquired at some point, and a serial with no date has no place in a FEFO or warranty question.
     */
    private function serial(Product $product, string $serial): ProductSerial
    {
        return ProductSerial::create([
            'product_id' => $product->getKey(),
            'serial' => $serial,
            'acquired_at' => now(),
        ]);
    }
}
