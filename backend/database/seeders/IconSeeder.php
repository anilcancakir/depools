<?php

namespace Database\Seeders;

use App\Models\Icon;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use RuntimeException;

/**
 * Loads the vendored icon catalogue into `icons`.
 *
 * The files come from `depools:vendor-icons`, which fetches them from Google and commits the result;
 * that command's docblock carries why the catalogue is vendored rather than fetched at deploy, and
 * why it is Material Symbols Outlined.
 *
 * ### Global, so it runs outside a tenant
 *
 * Unlike `DemoInventorySeeder` this touches nothing tenant-owned, so it needs no authenticated user
 * and no current team, and it deliberately does not guard on one. `Icon` carries no `team_id` and no
 * `TeamScope`, which is what makes that safe rather than lucky.
 *
 * ### Idempotent by upsert, not by "skip if any rows exist"
 *
 * A re-vendor that adds thirty icons and retags a hundred has to reach the table, and a
 * `if (Icon::exists()) return;` guard would silently keep the old catalogue forever. Upserting on
 * `name` means running this after a re-vendor does exactly what an operator expects.
 */
final class IconSeeder extends Seeder
{
    /**
     * Words this app's users type, added to the icons they mean.
     *
     * **Measured, not imagined.** Nine real queries were run against the catalogue as vendored, and
     * four returned nothing: `pantry`, `cupboard`, `basement` and `warehouse shelf`, plus `freezer`.
     * The first three are not a matching failure, they are absent: `select count(*) where search_text
     * like '%pantry%'` answers 0, and so do `cupboard`, `basement`, `cellar` and `larder`. Google's
     * tags are a general-purpose vocabulary and this is an inventory app, so the words a user reaches
     * for are not always the words the catalogue was tagged with.
     *
     * `freezer` is the fifth and a different kind of miss: nine icons carry `freez`, and every one
     * says `freeze`, `freezing` or `frozen`. Trigram similarity would reach it (0.42 against
     * `freezing`, 0.67 against `freeze`) at the cost of per-tag granularity, which means either a
     * 142,000-row join table or a similarity threshold to tune. One line here does the same job and
     * is legible.
     *
     * **Added to the tags rather than held in a second table**, so there is one place a search reads
     * from and no second query path to keep in step. The cost is that ours and Google's are mixed in
     * one column; the comment is the record of which is which, and every entry below is a word an
     * English-speaking user of THIS product would type.
     *
     * Not a translation layer. Turkish still finds nothing, and that is the AI suggestion's job
     * rather than something to fake here with a list that would go stale in one language and not
     * the other.
     *
     * @var array<string, list<string>>
     */
    private const EXTRA_TAGS = [
        // Rooms and places a tenant keeps stock in.
        'dining' => ['pantry', 'larder'],
        'door_sliding' => ['cupboard', 'wardrobe', 'closet'],
        'stairs' => ['basement', 'cellar'],
        'kitchen' => ['fridge'],
        'ac_unit' => ['freezer', 'chest freezer'],
        'countertops' => ['worktop', 'counter'],
        'shelves' => ['shelving', 'rack', 'racking'],
        'inventory_2' => ['carton', 'case'],
        'local_shipping' => ['van', 'truck', 'delivery vehicle'],
        'warehouse' => ['depot', 'stockroom', 'storeroom'],
        'garage' => ['carport'],
        'inbox' => ['drawer'],
        'shopping_basket' => ['basket'],
        'widgets' => ['crate'],
        'desk' => ['office'],
        'home' => ['house'],
    ];

    /**
     * How many rows per statement.
     *
     * The svg text averages 490 bytes, so 500 rows is roughly a quarter of a megabyte per insert:
     * large enough that 4,185 icons take a handful of statements, small enough to stay well inside
     * any parameter limit.
     */
    private const CHUNK = 500;

    public function run(): void
    {
        $catalogue = base_path('resources/icons/catalogue.ndjson');

        if (! is_file($catalogue)) {
            throw new RuntimeException(
                "No icon catalogue at [$catalogue]. Run `php artisan depools:vendor-icons` first; the "
                .'files are committed, so this usually means a partial checkout rather than a missing step.',
            );
        }

        $rows = [];
        $written = 0;
        $skipped = 0;
        $now = now();

        $handle = fopen($catalogue, 'rb');

        // `fopen` answers false on a permission or path problem, and `fgets(false)` then raises a
        // TypeError naming an argument rather than the file. A seeder that cannot read its own
        // catalogue should say which file.
        if ($handle === false) {
            throw new RuntimeException("Could not open the icon catalogue at [$catalogue].");
        }

        // Read line by line rather than loading the file: 1.8 MB is not large, but NDJSON exists
        // precisely so this stays a stream, and a catalogue that grows should not change this code.
        while (($line = fgets($handle)) !== false) {
            $line = trim($line);

            if ($line === '') {
                continue;
            }

            $icon = json_decode($line, true, 512, JSON_THROW_ON_ERROR);

            // **A row whose svg is missing is skipped, not stored empty.** An icon with no glyph is
            // worse than an absent one: it is pickable, it renders as nothing, and the failure
            // surfaces two screens away from its cause. The vendoring command already drops those,
            // so this is the second guard rather than the only one.
            if (! is_string($icon['svg'] ?? null) || ! str_starts_with($icon['svg'], '<svg')) {
                $skipped++;

                continue;
            }

            // **A missing name or title is fatal, where a missing svg is not, and the difference is
            // what each one means.** An icon without a glyph is one row the catalogue can do
            // without. A row with no name cannot be stored at all: both columns are NOT NULL, so
            // this would surface as an integrity violation naming a column rather than as the
            // truncated file it actually is.
            if (! is_string($icon['name'] ?? null) || ! is_string($icon['title'] ?? null)) {
                throw new RuntimeException(
                    'The icon catalogue has a row with no name or title. It is likely truncated; '
                    .'re-run `php artisan depools:vendor-icons --force`.',
                );
            }

            $tags = implode(', ', array_merge(
                $icon['tags'] ?? [],
                self::EXTRA_TAGS[$icon['name']] ?? [],
            ));

            $rows[] = [
                'id' => (string) Str::uuid7(),
                'name' => $icon['name'],
                'title' => $icon['title'],
                'category' => $icon['category'] ?? null,
                'tags' => $tags,
                'search_text' => Icon::searchTextFor($icon['name'], $icon['title'], $tags),
                'popularity' => (int) ($icon['popularity'] ?? 0),
                'svg' => $icon['svg'],
                'created_at' => $now,
                'updated_at' => $now,
            ];

            if (count($rows) >= self::CHUNK) {
                $written += $this->flush($rows);
                $rows = [];
            }
        }

        fclose($handle);

        if ($rows !== []) {
            $written += $this->flush($rows);
        }

        $this->command?->info("Seeded $written icons".($skipped > 0 ? ", skipped $skipped with no svg" : ''));
    }

    /**
     * Upsert one chunk, keyed on the name.
     *
     * `id` is absent from the update list on purpose: a re-seed must not hand an existing icon a new
     * primary key, because `locations.icon` stores the NAME and a changed id would be invisible here
     * while breaking anything that ever starts joining on it.
     *
     * @param  list<array<string, mixed>>  $rows
     */
    private function flush(array $rows): int
    {
        DB::table('icons')->upsert(
            $rows,
            ['name'],
            ['title', 'category', 'tags', 'search_text', 'popularity', 'svg', 'updated_at'],
        );

        return count($rows);
    }
}
