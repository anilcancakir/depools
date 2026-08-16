<?php

namespace Database\Seeders;

use App\Models\ProductCategory;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use RuntimeException;

/**
 * Loads the vendored Google taxonomy into `product_categories`.
 *
 * ### Why it runs from the migration rather than from `db:seed`
 *
 * The same reason `IconSeeder` does: this is not demo data a developer opts into, it is the shared
 * vocabulary `location_category_affinity` counts over. A tenant whose database skipped it has a
 * suggestion engine with nothing to say and no error explaining why.
 *
 * ### Inserted in file order, which is what makes the parents resolve
 *
 * The vendored file is written in the English source's order, and that file is sorted by path, so a
 * parent always precedes its children. Each row's parent is looked up in a map built as we go rather
 * than queried, which turns 5,595 parent lookups into none.
 *
 * ### Chunked, because 5,595 single inserts is a minute of a migration
 *
 * `insert` in batches of 500, with the timestamps set by hand: `insert` bypasses the model, so
 * nothing fills them and the columns are NOT NULL. That is the same trade `IconSeeder` makes, and
 * the same caveat applies: no model events fire here, so anything a model does on save has to be
 * done above instead. This table's model does nothing on save.
 */
final class TaxonomySeeder extends Seeder
{
    /**
     * Rows per insert.
     *
     * Five hundred keeps each statement well inside PostgreSQL's parameter limit at six columns plus
     * the keys, and it is the same figure the icon seed settled on.
     */
    private const CHUNK = 500;

    public function run(): void
    {
        $path = base_path('resources/taxonomy/taxonomy.ndjson');

        if (! is_file($path)) {
            throw new RuntimeException(
                "The taxonomy has not been vendored: {$path} is missing. Run `php artisan depools:vendor-taxonomy`.",
            );
        }

        // Idempotent, and cheaply: the seed either ran or it did not, and a partial run is not a
        // state this can reach because the whole thing is one transaction per chunk inside the
        // migration's own. Re-running would hit `UNIQUE NULLS NOT DISTINCT (team_id, path)` anyway.
        if (ProductCategory::query()->whereNull('team_id')->exists()) {
            return;
        }

        $now = now();

        /** @var array<int, string> $ids google_id => our own uuid */
        $ids = [];
        $batch = [];
        $written = 0;

        foreach (file($path, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [] as $line) {
            /** @var array<string, mixed> $row */
            $row = json_decode($line, true, 512, JSON_THROW_ON_ERROR);

            $googleId = (int) $row['google_id'];
            $parent = $row['parent_google_id'];

            // Generated here rather than by the database, because the NEXT row may name this one as
            // its parent and a foreign key cannot be filled from an id the insert has not returned.
            $id = (string) Str::uuid7();
            $ids[$googleId] = $id;

            if ($parent !== null && ! isset($ids[(int) $parent])) {
                // Unreachable while the file stays sorted, and the vendor command checks that too.
                // Kept because a silent orphan is a category that exists and can never be browsed to.
                throw new RuntimeException("Category {$googleId} names a parent that has not been inserted.");
            }

            $batch[] = [
                'id' => $id,
                // NULL is SHARED, which is what every row here is: the Google seed belongs to no
                // tenant and is the vocabulary they have in common.
                'team_id' => null,
                'parent_id' => $parent === null ? null : $ids[(int) $parent],
                'google_id' => $googleId,
                'name_en' => $row['name_en'],
                'name_tr' => $row['name_tr'],
                'path' => $row['path'],
                'depth' => (int) $row['depth'],
                'created_at' => $now,
                'updated_at' => $now,
            ];

            if (count($batch) >= self::CHUNK) {
                DB::table('product_categories')->insert($batch);
                $written += count($batch);
                $batch = [];
            }
        }

        if ($batch !== []) {
            DB::table('product_categories')->insert($batch);
            $written += count($batch);
        }

        if ($written === 0) {
            throw new RuntimeException('The taxonomy file was readable and held no rows.');
        }
    }
}
