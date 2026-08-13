<?php

namespace App\Console\Commands;

use App\Models\OffProduct;
use App\Support\Gtin;
use Illuminate\Console\Command;
use Illuminate\Support\Carbon;
use Illuminate\Support\Str;
use InvalidArgumentException;

/**
 * Loads the Open Food Facts export into `off_products`.
 *
 * ### Why a bulk import exists at all, when there is a live lookup
 *
 * `barcode-and-catalog.md` requires stages 1 to 3 to work OFFLINE, and a live query cannot. OFF asks
 * for the same thing from the other side: their API terms name one call per real scan and point at
 * the export for obtaining the database. So the export is the base and the live call is the top-up,
 * not the other way round.
 *
 * ### The file is not downloaded here, deliberately
 *
 * The export is roughly 0.9 GB compressed and 9 GB open. Fetching that inside a command turns a
 * failed download into a half-finished import with no obvious state, and it hides an operational
 * decision (which mirror, which cadence, how much disk) inside application code. The operator
 * downloads it and passes a path; this command's job is to be resumable and honest about progress.
 *
 * ### Columns are read by NAME and a missing one is fatal
 *
 * OFF's export has changed shape before and will again. Reading by position would silently import
 * brands into the name column; reading by name and failing loudly on an absent column turns a
 * schema change into a message rather than a corrupted table.
 */
final class ImportOpenFoodFacts extends Command
{
    protected $signature = 'depools:import-off
                            {file : Path to the Open Food Facts CSV/TSV export}
                            {--limit=0 : Stop after this many stored rows, 0 for all}
                            {--chunk=1000 : How many rows to upsert per statement}';

    protected $description = 'Import the Open Food Facts export into off_products';

    /**
     * The columns this import needs, mapped from OFF's own header names.
     *
     * `code` and `product_name` are required: a row without either cannot answer a scan, and storing
     * it would make the live top-up skip a product it could have fetched properly.
     */
    private const REQUIRED = ['code', 'product_name'];

    public function handle(): int
    {
        $path = (string) $this->argument('file');

        if (! is_readable($path)) {
            $this->error("Cannot read {$path}.");

            return self::FAILURE;
        }

        $handle = fopen($path, 'rb');

        if ($handle === false) {
            $this->error("Cannot open {$path}.");

            return self::FAILURE;
        }

        // Tab, because OFF's CSV export is tab-separated despite the extension. A comma would parse
        // the whole line as one column and the header check below is what would catch it.
        $separator = "\t";
        $header = fgetcsv($handle, 0, $separator);

        if ($header === false) {
            fclose($handle);

            $this->error('The file is empty.');

            return self::FAILURE;
        }

        /** @var array<string, int> $columns */
        $columns = array_flip(array_map(static fn ($name): string => trim((string) $name), $header));

        foreach (self::REQUIRED as $name) {
            if (! isset($columns[$name])) {
                fclose($handle);

                $this->error("The export has no `{$name}` column. OFF changed its shape; this import needs updating rather than guessing.");

                return self::FAILURE;
            }
        }

        $limit = (int) $this->option('limit');
        $chunkSize = max(1, (int) $this->option('chunk'));

        $stored = 0;
        $skipped = 0;
        $buffer = [];

        while (($row = fgetcsv($handle, 0, $separator)) !== false) {
            $candidate = $this->row($row, $columns);

            if ($candidate === null) {
                $skipped++;

                continue;
            }

            $buffer[] = $candidate;
            $stored++;

            if (count($buffer) >= $chunkSize) {
                $this->flush($buffer);
                $buffer = [];
                $this->line("stored {$stored}, skipped {$skipped}");
            }

            if ($limit > 0 && $stored >= $limit) {
                break;
            }
        }

        if ($buffer !== []) {
            $this->flush($buffer);
        }

        fclose($handle);

        $this->info("Imported {$stored} products, skipped {$skipped} rows with no usable barcode or name.");

        return self::SUCCESS;
    }

    /**
     * One export row as an `off_products` row, or null when it cannot answer a scan.
     *
     * @param  list<string|null>  $row
     * @param  array<string, int>  $columns
     * @return array<string, mixed>|null
     */
    private function row(array $row, array $columns): ?array
    {
        $code = $this->value($row, $columns, 'code');
        $name = $this->value($row, $columns, 'product_name');

        if ($code === null || $name === null) {
            return null;
        }

        try {
            $gtin = (string) Gtin::fromScan($code);
        } catch (InvalidArgumentException) {
            // OFF holds internal codes and malformed entries alongside real GTINs. One that cannot be
            // a GTIN cannot be scanned into this app, so it is skipped rather than stored under a
            // key nothing will ever look up.
            return null;
        }

        return [
            // **The key is generated here because `upsert` writes rows directly.** It fires no model
            // event, so `ConditionallyUsesUuids` never runs and PostgreSQL refuses the null id. Same
            // trap the pivot models carry a comment about: `attach()` bypasses the model the same
            // way. An ordered uuid rather than a random one, to match what the trait produces.
            'id' => (string) Str::orderedUuid(),
            'gtin' => $gtin,
            'name' => mb_substr($name, 0, 255),
            // **And the fold, for the same reason as the key.** `NormalisesName` keeps this in step
            // with `name` through a model event, which `upsert` does not fire, and the column is NOT
            // NULL. Computed through the trait's own static so the import cannot drift from the fold
            // the cascade searches by; `StockConsistency`'s `name_normalized_drift` check is what
            // would catch it if it ever did.
            'name_normalized' => OffProduct::normaliseName(mb_substr($name, 0, 255)),
            'brand' => $this->value($row, $columns, 'brands'),
            'locale' => $this->locale($this->value($row, $columns, 'lang')),
            'off_category' => $this->value($row, $columns, 'main_category'),
            'image_url' => $this->value($row, $columns, 'image_url'),
            'source_ref' => 'off:export:'.$gtin,
            'imported_at' => Carbon::now(),
            'created_at' => Carbon::now(),
            'updated_at' => Carbon::now(),
        ];
    }

    /**
     * @param  list<array<string, mixed>>  $rows
     */
    private function flush(array $rows): void
    {
        // Upsert on the GTIN, so a re-run over a newer export updates rather than failing on the
        // unique index. That is what makes the 14-day delta files usable: the same command, a
        // smaller file.
        OffProduct::query()->upsert(
            $rows,
            ['gtin'],
            ['name', 'name_normalized', 'brand', 'locale', 'off_category', 'image_url', 'source_ref', 'imported_at', 'updated_at'],
        );
    }

    /**
     * @param  list<string|null>  $row
     * @param  array<string, int>  $columns
     */
    private function value(array $row, array $columns, string $name): ?string
    {
        $index = $columns[$name] ?? null;

        if ($index === null) {
            return null;
        }

        $value = trim((string) ($row[$index] ?? ''));

        return $value === '' ? null : mb_substr($value, 0, 255);
    }

    private function locale(?string $lang): string
    {
        // The column is `string(5)` and OFF's `lang` is ISO-639-1. Anything else falls back to
        // English rather than being stored malformed: the locale decides who sees this row without
        // translation, so a wrong one is worse than a default.
        return $lang !== null && preg_match('/^[a-z]{2}$/', $lang) === 1 ? $lang : 'en';
    }
}
