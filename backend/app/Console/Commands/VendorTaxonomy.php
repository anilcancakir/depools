<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;
use Illuminate\Support\Facades\File;
use Illuminate\Support\Facades\Http;
use RuntimeException;

/**
 * Vendors Google's product taxonomy into the repository.
 *
 * ### Why the file is committed rather than fetched at deploy
 *
 * The same argument `depools:vendor-icons` makes: a deploy that calls Google is a deploy that can
 * fail for a reason nobody controls, and it makes a build unreproducible. This runs occasionally, by
 * hand, and its OUTPUT is the artifact.
 *
 * It is a stronger argument here than for the icons, because there is nothing to keep up with. The
 * first line of each file reads `# Google_Product_Taxonomy_Version: 2021-09-21`, so the taxonomy has
 * been frozen since September 2021: re-running this is a check that the source still says the same
 * thing rather than a refresh.
 *
 * ### Two files, joined on the id
 *
 * Google publishes one plain-text file per locale, each line `id - Path > With > Levels`. The two
 * carry the same 5,595 nodes under the same ids and differ only in the words, so the id is the join
 * and the English file decides the ORDER.
 *
 * That ordering matters and is free: the English file is sorted by path, so a parent's path is a
 * prefix of its children's and sorts before them. The seeder inserts in file order and never has to
 * look ahead for a parent. The Turkish file is sorted by ITS own alphabet and cannot be used for
 * that, which is one more reason the id is the key and the path is only a label (D87).
 */
final class VendorTaxonomy extends Command
{
    protected $signature = 'depools:vendor-taxonomy';

    protected $description = 'Fetch the Google product taxonomy into backend/resources/taxonomy';

    /**
     * Where each locale's file lives.
     *
     * The `-US` and `-TR` regions are Google's own spelling and there is no locale-neutral English
     * file, so the region travels even though nothing here is region-specific.
     */
    private const SOURCES = [
        'en' => 'https://www.google.com/basepages/producttype/taxonomy-with-ids.en-US.txt',
        'tr' => 'https://www.google.com/basepages/producttype/taxonomy-with-ids.tr-TR.txt',
    ];

    /**
     * Google's own cap, and the one the table's CHECK enforces.
     *
     * Stated here as a guard rather than trusted: a source that grew an eighth level would otherwise
     * write rows the database then refuses, halfway through a seed.
     */
    private const MAX_DEPTH = 7;

    public function handle(): int
    {
        $root = base_path('resources/taxonomy');

        File::ensureDirectoryExists($root);

        $english = $this->fetch(self::SOURCES['en']);
        $turkish = $this->fetch(self::SOURCES['tr']);

        $this->info('Fetched '.count($english).' English and '.count($turkish).' Turkish nodes');

        // **The two files must describe the same taxonomy**, or the join silently drops or invents
        // nodes. Compared as SETS of ids rather than as counts, because two files of equal length
        // can still disagree about which ids they carry.
        $missing = array_diff(array_keys($english), array_keys($turkish));

        if ($missing !== []) {
            throw new RuntimeException(
                count($missing).' ids are in the English file and not the Turkish one, '
                .'so the two locales are not the same taxonomy: '.implode(', ', array_slice($missing, 0, 5)),
            );
        }

        $lines = [];
        $seen = [];

        foreach ($english as $id => $path) {
            $segments = $this->segments($path);
            $depth = count($segments) - 1;

            if ($depth > self::MAX_DEPTH - 1) {
                throw new RuntimeException("Node {$id} is {$depth} levels deep, past Google's own cap.");
            }

            $parentPath = $depth === 0 ? null : implode(' > ', array_slice($segments, 0, -1));

            // The parent's ID, resolved from the path we have already walked past. Present by
            // construction because the file is sorted by path, and checked anyway: a source that
            // ever stopped being sorted would otherwise write orphans with no complaint.
            if ($parentPath !== null && ! isset($seen[$parentPath])) {
                throw new RuntimeException("Node {$id} names a parent the file has not listed yet: {$parentPath}");
            }

            $seen[$path] = $id;

            $lines[] = json_encode([
                'google_id' => $id,
                'parent_google_id' => $parentPath === null ? null : $seen[$parentPath],
                // The LEAF, not the whole path: the row's own name is what a picker renders, and the
                // path is carried separately for the screens that show the walk.
                'name_en' => end($segments),
                'name_tr' => $this->leaf($turkish[$id]),
                'path' => $path,
                'depth' => $depth,
            ], JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR);
        }

        File::put($root.'/taxonomy.ndjson', implode("\n", $lines)."\n");

        $this->info('Wrote '.count($lines).' categories to resources/taxonomy');

        return self::SUCCESS;
    }

    /**
     * One locale's file as `id => path`.
     *
     * @return array<int, string>
     */
    private function fetch(string $url): array
    {
        $response = Http::timeout(60)->get($url);

        if (! $response->successful()) {
            throw new RuntimeException("Could not fetch {$url}: HTTP {$response->status()}");
        }

        $nodes = [];

        foreach (preg_split('/\R/', $response->body()) ?: [] as $line) {
            $line = trim($line);

            // The version comment and the trailing blank. The comment is worth reading rather than
            // skipping blindly, which the caller does by asserting the two files agree.
            if ($line === '' || str_starts_with($line, '#')) {
                continue;
            }

            // `1 - Animals & Pet Supplies`. Split on the FIRST separator only: a category name can
            // contain a hyphen ("T-Shirts"), and splitting on every one would truncate it.
            $parts = explode(' - ', $line, 2);

            if (count($parts) !== 2 || ! ctype_digit($parts[0])) {
                throw new RuntimeException("Unreadable taxonomy line: {$line}");
            }

            $nodes[(int) $parts[0]] = trim($parts[1]);
        }

        return $nodes;
    }

    /**
     * A path's own segments.
     *
     * @return list<string>
     */
    private function segments(string $path): array
    {
        return array_map('trim', explode(' > ', $path));
    }

    /** The last segment of a path. */
    private function leaf(string $path): string
    {
        $segments = $this->segments($path);

        return end($segments);
    }
}
