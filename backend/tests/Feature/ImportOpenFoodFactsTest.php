<?php

namespace Tests\Feature;

use App\Models\OffProduct;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * The Open Food Facts bulk import.
 *
 * The properties worth pinning are the ones that fail SILENTLY: a shape change in somebody else's
 * export, and a row that is stored under a key nothing will ever look up. Both leave a table that
 * looks full and answers nothing.
 */
final class ImportOpenFoodFactsTest extends TestCase
{
    use RefreshDatabase;

    private function export(string $body): string
    {
        $path = tempnam(sys_get_temp_dir(), 'off').'.csv';

        file_put_contents($path, $body);

        return $path;
    }

    private function tsv(array $rows): string
    {
        return implode("\n", array_map(static fn (array $row): string => implode("\t", $row), $rows))."\n";
    }

    public function test_it_imports_rows_that_can_answer_a_scan(): void
    {
        $path = $this->export($this->tsv([
            ['code', 'product_name', 'brands', 'lang', 'image_url', 'main_category'],
            ['8690504010012', 'Süt 1 L', 'Pınar', 'tr', 'https://img/1.jpg', 'en:milk'],
        ]));

        $this->artisan('depools:import-off', ['file' => $path])->assertSuccessful();

        $this->assertDatabaseHas('off_products', [
            // Stored as GTIN-14 rather than as OFF's own 13, because GS1 says so and the rest of the
            // app keys on that. The live lookup strips the padding back off when it asks OFF.
            'gtin' => '08690504010012',
            'name' => 'Süt 1 L',
            'brand' => 'Pınar',
            'locale' => 'tr',
        ]);
    }

    public function test_a_row_with_no_name_is_skipped_rather_than_stored_empty(): void
    {
        // **A named row is the whole point.** Storing a nameless one would make the live top-up skip
        // a product it could have fetched properly, so the table would answer with nothing useful
        // and never try again.
        $path = $this->export($this->tsv([
            ['code', 'product_name'],
            ['8690504010012', ''],
            ['8690504010029', 'Real Product'],
        ]));

        $this->artisan('depools:import-off', ['file' => $path])->assertSuccessful();

        $this->assertSame(1, OffProduct::query()->count());
        $this->assertSame('Real Product', OffProduct::query()->value('name'));
    }

    public function test_a_code_that_cannot_be_a_gtin_is_skipped(): void
    {
        // OFF holds internal codes and malformed entries beside real GTINs. One that cannot be
        // scanned into this app must not be stored under a key nothing will ever look up.
        $path = $this->export($this->tsv([
            ['code', 'product_name'],
            ['not-a-barcode', 'Nonsense'],
            ['012345678901234567', 'Too Long'],
            ['8690504010012', 'Real Product'],
        ]));

        $this->artisan('depools:import-off', ['file' => $path])->assertSuccessful();

        $this->assertSame(1, OffProduct::query()->count());
    }

    public function test_a_missing_column_fails_loudly_instead_of_importing_the_wrong_field(): void
    {
        // **The failure this test exists for is silent.** OFF's export has changed shape before;
        // reading by position would put brands into the name column and the table would look full
        // and be wrong. Reading by name and refusing turns that into a message.
        $path = $this->export($this->tsv([
            ['code', 'brands'],
            ['8690504010012', 'Pınar'],
        ]));

        $this->artisan('depools:import-off', ['file' => $path])
            ->expectsOutputToContain('product_name')
            ->assertFailed();

        $this->assertSame(0, OffProduct::query()->count());
    }

    public function test_a_second_run_updates_rather_than_failing_on_the_unique_index(): void
    {
        // This is what makes OFF's 14-day delta files usable: the same command, a smaller file.
        $first = $this->export($this->tsv([
            ['code', 'product_name'],
            ['8690504010012', 'Old Name'],
        ]));

        $second = $this->export($this->tsv([
            ['code', 'product_name'],
            ['8690504010012', 'Corrected Name'],
        ]));

        $this->artisan('depools:import-off', ['file' => $first])->assertSuccessful();
        $this->artisan('depools:import-off', ['file' => $second])->assertSuccessful();

        $this->assertSame(1, OffProduct::query()->count());
        $this->assertSame('Corrected Name', OffProduct::query()->value('name'));
    }

    public function test_the_limit_stops_early_so_a_local_import_can_be_small(): void
    {
        $path = $this->export($this->tsv([
            ['code', 'product_name'],
            ['8690504010012', 'One'],
            ['8690504010029', 'Two'],
            ['8690504010036', 'Three'],
        ]));

        $this->artisan('depools:import-off', ['file' => $path, '--limit' => 2])->assertSuccessful();

        $this->assertSame(2, OffProduct::query()->count());
    }
}
