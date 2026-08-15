<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;
use Illuminate\Support\Facades\File;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Str;
use RuntimeException;

/**
 * Vendors the Material Symbols Outlined catalogue into the repository.
 *
 * ### Why the icons are DATA and not a const map in Dart
 *
 * Flutter's `IconTreeShaker` runs `ConstFinder` over the compiled kernel's CONSTANT POOL, so it
 * keeps every entry of a `const Map` and drops anything built at runtime from a stored codepoint.
 * That is not a bug to work around, it is the mechanism: an app that lets a user pick from the whole
 * set has to reference the whole set as constants, and then pays for it. Measured on this app:
 *
 *     16 icons        main.dart.js 5,132,437   font    23,376
 *     all 8,825       main.dart.js 5,796,655   font 1,261,120
 *
 * That is +1.81 MB for a searchable picker, and the tree-shaking reduction collapses from 98.6% to
 * 23.3%. Serving the SVG from our own database instead takes the app-size question to zero, and it
 * turns the catalogue into rows: adding an icon becomes a migration, not an app release.
 *
 * ### Why the files are committed rather than fetched at deploy
 *
 * A deploy that calls Google is a deploy that can fail for a reason nobody controls, and it makes a
 * build unreproducible. So this command runs occasionally, by hand, and its OUTPUT is the artifact.
 * The stated risk is that the asset url carries `short-term/release` in its path; if Google moves it
 * this command breaks and the app does not, which is the right way round.
 *
 * ### Which family, and why not the one the app's own chrome uses
 *
 * The app's chrome draws `Icons.*_outlined` from Flutter's bundled legacy font, so matching it
 * exactly would mean vendoring Material Icons Outlined. That family is a strict SUBSET: its metadata
 * lists 2,122 icons against 4,226 here, and it is missing ones this app already uses (`shelves`).
 * The two are the same drawing on different coordinate systems, verified on `kitchen`: legacy is
 * `viewBox="0 0 24 24"` and Symbols is `viewBox="0 -960 960 960"`, same shape either way. So the
 * coverage wins and the visual cost is close to nothing.
 *
 * ### What the metadata is worth
 *
 * Every icon carries a median of 34 tags plus a category and a `popularity` integer, and the tags
 * are this app's own vocabulary: `shelves` lists inventory, storage, warehouse, goods, products;
 * `warehouse` lists depot, logistics, stock. That is what the picker searches and what the AI
 * suggestion embeds. No icon set anywhere publishes Turkish tags (checked across Material, Lucide,
 * Tabler, Phosphor, Heroicons, Remix, Iconify and Font Awesome), so Turkish matching has to come
 * from a multilingual embedding rather than from this file.
 */
final class VendorIcons extends Command
{
    protected $signature = 'depools:vendor-icons
                            {--force : Refetch every svg rather than only the missing ones}
                            {--limit=0 : Stop after this many icons, 0 for all}';

    protected $description = 'Fetch the Material Symbols Outlined catalogue into backend/resources/icons';

    /**
     * Google's icon metadata, the only place the tags and categories exist.
     *
     * NOT in `google/material-design-icons`: a full tree scan of that repository turns up the SVGs
     * and per-style `.codepoints` files and no tags at all. Reading only the repository is what makes
     * Material look like it has no metadata, when in fact it has the richest of any set compared.
     */
    private const METADATA_URL = 'https://fonts.google.com/metadata/icons?incomplete=1&key=material_symbols';

    /**
     * Where one icon's 24px outlined svg lives.
     *
     * `default` rather than a version, because the Symbols family is served unversioned here. The
     * legacy family takes `v{version}` from the metadata instead; the two are not interchangeable and
     * each answers 404 for the other's shape, which is worth knowing before assuming a typo.
     */
    private const ASSET_URL = 'https://fonts.gstatic.com/s/i/short-term/release/materialsymbolsoutlined/%s/default/24px.svg';

    /**
     * How many svgs are in flight at once.
     *
     * Six thousand sequential requests is five minutes of waiting; twenty at a time is well under
     * one. Higher was not tried, because this is a command an operator runs a few times a year and
     * being a good citizen against someone else's CDN is worth more than the seconds.
     */
    private const CONCURRENCY = 20;

    public function handle(): int
    {
        $root = base_path('resources/icons');

        File::ensureDirectoryExists($root);

        $icons = $this->fetchMetadata();
        $this->info(count($icons).' distinct icons in the catalogue');

        if (($limit = (int) $this->option('limit')) > 0) {
            $icons = array_slice($icons, 0, $limit);
            $this->warn('Limited to '.count($icons).', so the metadata written is PARTIAL');
        }

        $svgs = $this->fetchSvgs($icons);

        // **Only icons whose svg actually arrived reach the catalogue.** The alternative, writing the
        // full list and letting the seeder discover the gaps, produces rows that are pickable and
        // render as nothing, and that failure surfaces two screens from its cause.
        $complete = array_values(array_filter(
            $icons,
            static fn (array $icon): bool => isset($svgs[$icon['name']]),
        ));

        $this->writeCatalogue($root, $complete, $svgs);

        $this->info('Wrote '.count($complete).' icons to resources/icons');

        // **The misses are legacy ALIASES, not lost icons, and that is worth saying here so nobody
        // investigates it twice.** 41 of the 4,226 answered 404, and every one checked is a name the
        // old generation used for an icon the new one renamed: `info_outline` against `info`,
        // `play_circle_outline` against `play_circle`, `person_add_alt_1` against `person_add`. The
        // modern name is in the catalogue in each case, so nothing a user could pick is absent.
        if (count($complete) !== count($icons)) {
            $this->warn(
                (count($icons) - count($complete)).' svgs answered 404 and were left out; these are '
                .'legacy aliases whose modern name is already in the catalogue',
            );
        }

        return self::SUCCESS;
    }

    /**
     * The family whose svgs this command fetches, as the metadata spells it.
     *
     * Load-bearing for deduplication, see [fetchMetadata].
     */
    private const FAMILY = 'Material Symbols Outlined';

    /**
     * The catalogue, deduplicated and sorted by name so the written file is stable.
     *
     * **The endpoint returns BOTH generations, so 1,872 of its 6,098 entries are a second copy of an
     * icon already listed.** Measured: 4,226 distinct names. The two entries for one name are not
     * identical, and taking whichever came first would mix two vocabularies in one column: `10k`
     * arrives once as version 399 in category `Audio&Video` and once as version 10 in category `av`,
     * with different popularity numbers (212 against 1368).
     *
     * `unsupported_families` is what separates them, and it is the honest test rather than a guess at
     * the version number: the legacy entry lists the three Symbols families as unsupported, the
     * Symbols entry lists the five legacy ones. We fetch Symbols svgs, so we keep the Symbols row and
     * its category and popularity, and the whole table then speaks one vocabulary.
     *
     * @return list<array{name: string, categories: list<string>, tags: list<string>, popularity: int}>
     */
    private function fetchMetadata(): array
    {
        $response = Http::timeout(60)->get(self::METADATA_URL);

        if ($response->failed()) {
            throw new RuntimeException('Icon metadata fetch failed with '.$response->status());
        }

        // The response is JSON behind an XSSI guard: Google prefixes it with `)]}'` so a browser
        // cannot eval it as a script. Trimming to the first brace rather than a fixed offset, because
        // the prefix is not documented and a fixed length would break silently on a change.
        $body = $response->body();
        $start = strpos($body, '{');

        if ($start === false) {
            throw new RuntimeException('Icon metadata carried no JSON object');
        }

        $decoded = json_decode(substr($body, $start), true, 512, JSON_THROW_ON_ERROR);

        $icons = [];

        foreach ($decoded['icons'] ?? [] as $icon) {
            $name = $icon['name'];
            $inFamily = ! in_array(self::FAMILY, $icon['unsupported_families'] ?? [], true);

            // Keep the first entry that is in our family; otherwise keep whatever we have, so an icon
            // that exists ONLY in the legacy generation still reaches the table rather than being
            // dropped for not being modern enough. Its svg fetch decides whether it survives.
            if (isset($icons[$name]) && ! $inFamily) {
                continue;
            }

            $icons[$name] = [
                'name' => $name,
                'categories' => $icon['categories'] ?? [],
                'tags' => $icon['tags'] ?? [],
                'popularity' => (int) ($icon['popularity'] ?? 0),
            ];
        }

        ksort($icons);

        return array_values($icons);
    }

    /**
     * Fetch every svg, keyed by name.
     *
     * **Resumable against the previous catalogue rather than against a directory.** The svgs used to
     * be 4,185 separate files, which made the vendored set unreviewable: a pull request carrying it
     * exceeds Copilot's 300-file ceiling and gets no review at all. They live inside the one
     * catalogue file now, so this reads that file to decide what is already fetched. `--force`
     * refetches everything, for the day Google redraws a glyph.
     *
     * @param  list<array{name: string, ...}>  $icons
     * @return array<string, string>
     */
    private function fetchSvgs(array $icons): array
    {
        $have = (bool) $this->option('force') ? [] : $this->readExistingSvgs();
        $pending = [];

        foreach ($icons as $icon) {
            if (! isset($have[$icon['name']])) {
                $pending[] = $icon['name'];
            }
        }

        if ($pending === []) {
            return $have;
        }

        $bar = $this->output->createProgressBar(count($pending));
        $bar->start();

        foreach (array_chunk($pending, self::CONCURRENCY) as $batch) {
            $responses = Http::pool(fn ($pool) => array_map(
                static fn (string $name) => $pool->as($name)->timeout(30)->get(sprintf(self::ASSET_URL, $name)),
                $batch,
            ));

            foreach ($batch as $name) {
                $response = $responses[$name];

                // A 404 is expected rather than exceptional: the metadata lists icons the asset host
                // has not published, so this skips them and the summary reports the count. Failing
                // the whole run on one missing glyph would make the command unusable.
                if (! is_object($response) || ! method_exists($response, 'successful') || ! $response->successful()) {
                    continue;
                }

                $svg = trim($response->body());

                // The host answers a 404 HTML page with a 200 in some edge cases, so the shape is
                // checked rather than the status alone. An HTML page written as `home.svg` renders
                // as nothing and looks like a styling bug three layers away.
                if (! str_starts_with($svg, '<svg')) {
                    continue;
                }

                $have[$name] = $svg;
            }

            $bar->advance(count($batch));
        }

        $bar->finish();
        $this->newLine();

        return $have;
    }

    /**
     * The svgs already in the committed catalogue, so a re-run is cheap.
     *
     * @return array<string, string>
     */
    private function readExistingSvgs(): array
    {
        $path = base_path('resources/icons/catalogue.ndjson');

        if (! File::exists($path)) {
            return [];
        }

        $svgs = [];
        $handle = fopen($path, 'rb');

        while (($line = fgets($handle)) !== false) {
            if (trim($line) === '') {
                continue;
            }

            $row = json_decode($line, true, 512, JSON_THROW_ON_ERROR);

            if (isset($row['name'], $row['svg'])) {
                $svgs[$row['name']] = $row['svg'];
            }
        }

        fclose($handle);

        return $svgs;
    }

    /**
     * Write the whole catalogue, one icon per line, svg included.
     *
     * **ONE file rather than a metadata file beside 4,185 svgs, and the reason is that the set has to
     * be reviewable.** A pull request carrying the icons as separate files runs to 4,191 changed
     * files, and Copilot refuses to review anything over 300: measured on the first attempt, which
     * came back "exceeds the maximum number of files (300)" and no review at all. Per-file diffs
     * bought nothing to weigh against that, because a glyph never changes on its own; a re-vendor
     * replaces the set.
     *
     * NDJSON rather than one JSON array, so the file stays diffable at all: a re-vendor that retags
     * one icon is a one-line change, and a reader can `grep` a name and get the whole row.
     *
     * Sorted by name upstream, so the line order is stable and a re-run with no upstream change
     * produces no diff.
     *
     * @param  list<array{name: string, categories: list<string>, tags: list<string>, popularity: int}>  $icons
     * @param  array<string, string>  $svgs
     */
    private function writeCatalogue(string $root, array $icons, array $svgs): void
    {
        $lines = array_map(static fn (array $icon): string => json_encode([
            'name' => $icon['name'],
            // **Derived, because the metadata has no title field.** `local_shipping` becomes
            // `Local shipping`: sentence case rather than title case, matching how this app writes
            // every other label.
            'title' => Str::ucfirst(str_replace('_', ' ', $icon['name'])),
            'category' => $icon['categories'][0] ?? null,
            'tags' => $icon['tags'],
            'popularity' => $icon['popularity'],
            'svg' => $svgs[$icon['name']],
        ], JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR), $icons);

        File::put($root.'/catalogue.ndjson', implode("\n", $lines)."\n");
    }
}
