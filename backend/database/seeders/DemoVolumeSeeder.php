<?php

namespace Database\Seeders;

use App\Models\Location;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Scopes\TeamScope;
use App\Services\StockWriter;
use Illuminate\Database\Seeder;
use Illuminate\Support\Carbon;
use RuntimeException;

/**
 * Bulk products, for the questions a curated fixture cannot answer.
 *
 * [DemoInventorySeeder] is eleven products chosen so every status badge has a row, and that is the
 * right shape for judging a screen. It is the wrong shape for judging a LIST: filters that match
 * three of eleven prove nothing about a filter, a search over eleven names never has to be fast, and
 * a hundred rows is where a column that wanders or a row that rebuilds too often becomes visible.
 *
 * So this is deliberately the opposite kind of data. It is generated rather than curated, and the
 * only thing designed about it is the SPREAD: every filter axis has enough rows on both sides of it
 * to be worth applying.
 *
 * ### Opt-in, and it runs after the curated set
 *
 * `DEMO_VOLUME=90 php artisan db:seed`. Off by default, because the eleven are what the screens were
 * designed against and burying them under ninety generated rows would make every future screenshot
 * harder to read, not easier.
 *
 * ### Everything goes through the writer, at a cost worth knowing
 *
 * Ninety products with stock is a few hundred `StockWriter` calls, each in its own transaction with
 * its own projection rebuild, so this takes seconds rather than milliseconds. Inserting rows directly
 * would be faster and would produce a fixture that disagrees with the ledger, which is the failure
 * D81 exists to prevent and the reason `DemoSeederTest` sweeps for drift afterwards.
 */
class DemoVolumeSeeder extends Seeder
{
    /** Brands, with a deliberate gap: a product with no brand is a real row and the filter has to cope. */
    private const BRANDS = ['Pınar', 'Meadow', 'Kronotrop', 'Şölen', 'Torku', null, null];

    /** Tags, so the tag axis has overlapping sets rather than one tag per product. */
    private const TAGS = ['kahvaltı', 'temizlik', 'kuru gıda', 'içecek', 'atıştırmalık', 'bakliyat'];

    /** Category names, shallow on purpose: the tree is the taxonomy import's job, not this fixture's. */
    private const CATEGORIES = ['Dairy', 'Bakery', 'Cleaning', 'Beverages', 'Dry Goods'];

    /**
     * Noun parts, combined into names of varied length so the list has short rows, long rows and the
     * truncation case rather than ninety names of the same width.
     */
    private const HEADS = [
        'Süzme Peynir', 'Tam Yağlı Süt', 'Kaşar', 'Tereyağı', 'Zeytinyağı', 'Ayçiçek Yağı',
        'Pirinç', 'Bulgur', 'Mercimek', 'Nohut', 'Şeker', 'Tuz', 'Karabiber', 'Salça',
        'Makarna', 'Un', 'Yumurta', 'Bal', 'Reçel', 'Çay', 'Kahve', 'Bulaşık Deterjanı',
        'Çamaşır Suyu', 'Kağıt Havlu', 'Peçete', 'Islak Mendil', 'Sabun', 'Şampuan',
        'Maden Suyu', 'Meyve Suyu',
    ];

    private const QUALIFIERS = ['', ' Klasik', ' Light', ' Organik', ' Extra', ' Cold Pressed, Reserve Selection'];

    private const SIZES = ['', ' 500 g', ' 1 kg', ' 750 ml', ' 1 L', ' 250 g', ' 12-Pack'];

    public function run(): void
    {
        // Its own guards, not a reliance on [DatabaseSeeder]'s. Trusting the other entry point is
        // exactly what makes a second entry point dangerous: reached through `db:seed --class=` this
        // runs with no tenant, `BelongsToTeam` stamps a null `team_id`, and the first insert dies on
        // a NOT NULL naming a column with nothing in it about seeding.
        if (! app()->environment(['local', 'testing'])) {
            throw new RuntimeException('The volume seeder only runs in local or testing.');
        }

        if (TeamScope::currentTeamId() === null) {
            throw new RuntimeException(
                'No current team resolved, so every insert would fail on a NOT NULL. Run `db:seed` '
                .'with DEMO_VOLUME set rather than this class alone, and let DatabaseSeeder '
                .'authenticate the demo user first.',
            );
        }

        $count = (int) env('DEMO_VOLUME', 0);

        if ($count <= 0) {
            return;
        }

        $locations = Location::query()->whereNotNull('parent_location_id')->get();

        if ($locations->isEmpty()) {
            throw new RuntimeException('No leaf locations to put stock in; run the inventory seeder first.');
        }

        $categories = collect(self::CATEGORIES)->map(
            fn (string $name): ProductCategory => ProductCategory::create([
                'team_id' => TeamScope::currentTeamId(),
                'name_en' => $name,
                'name_tr' => $name,
                'path' => $name,
                'depth' => 0,
            ]),
        );

        $writer = app(StockWriter::class);
        $today = Carbon::today();

        // **Every value below is derived from the index, with no randomness anywhere.** A generated
        // fixture is only useful if it is the same fixture twice: a defect found on row 47 has to be
        // reproducible, and a screenshot has to still match next week. Randomness would make both a
        // matter of luck, and the spread the filters need is a property of the proportions rather
        // than of any single row being surprising.
        for ($i = 0; $i < $count; $i++) {
            $name = self::HEADS[$i % count(self::HEADS)]
                .self::QUALIFIERS[$i % count(self::QUALIFIERS)]
                .self::SIZES[$i % count(self::SIZES)]
                .' #'.($i + 1);

            // A content declaration on a third of them, and the base unit stays the COUNTABLE one:
            // `piece` holding 500 g, never `g` holding 500 g. The second shape says a gram contains
            // 500 grams and `POST /products` now refuses it.
            $hasContent = $i % 3 === 0;

            $product = Product::create([
                'name' => $name,
                'brand' => self::BRANDS[$i % count(self::BRANDS)],
                'sku' => $i % 4 === 0 ? 'SKU-'.str_pad((string) ($i + 1), 4, '0', STR_PAD_LEFT) : null,
                'base_unit' => 'C62',
                'product_category_id' => $i % 5 === 0 ? null : $categories[$i % $categories->count()]->getKey(),
                'tracks_expiry' => $i % 4 !== 0,
                'default_shelf_life_days' => $i % 4 !== 0 ? 7 + ($i % 60) : null,
                // **An opened clock without a printed date is deliberate, not a contradiction.**
                // `data-model.md` defines `tracks_expiry` as "when true, capture asks for an expiry
                // date", so it is about what capture PROMPTS for, not about whether a product can ever
                // have a deadline. A jar with nothing printed on it that has to be used within five
                // days of opening is exactly this shape, and `StockLot::bindingDate()` returning the
                // opened deadline when `expires_at` is null is that case working rather than leaking.
                //
                // It is also the only place the fixture reaches that branch: measured, 8 products here
                // have it and 3 of them carry an opened lot whose binding date comes from the clock
                // alone, against 0 of the curated eleven. A review flagged it as skewing the expiry
                // filters; those products genuinely have a deadline, so the filter including them is
                // correct.
                'opened_shelf_life_days' => $hasContent ? 3 + ($i % 5) : null,
                'content_amount' => $hasContent ? ($i % 2 === 0 ? 500 : 1000) : null,
                'content_unit' => $hasContent ? ($i % 2 === 0 ? 'g' : 'ml') : null,
                'par_level' => 2 + ($i % 8),
                'reorder_point' => 1 + ($i % 4),
            ]);

            // Two tags on some, one on others, none on the rest: the tag filter needs overlapping
            // sets to be worth anything, and an untagged product is a real row.
            //
            // **The stride is 7 because the tag list has 6 entries, and that is not a detail.** It was
            // `$i % 3 !== 2`, and 3 divides 6, so `kuru gıda` (index 2) and `bakliyat` (index 5) landed
            // on a skipped row EVERY time: the tag axis offered four options instead of six and the
            // fixture looked fine. A modulo fixture is only as varied as its strides are coprime, and
            // that is exactly the kind of gap generated data hides.
            if ($i % 7 !== 6) {
                $product->syncTags([
                    self::TAGS[$i % count(self::TAGS)],
                    ...($i % 6 === 0 ? [self::TAGS[($i + 3) % count(self::TAGS)]] : []),
                ]);
            }

            $location = $locations[$i % $locations->count()];

            // The spread that makes the filters testable, in the proportions a real shelf has: mostly
            // fine, a tenth gone, a fifth low, and a sixth of the dated ones already past or nearly.
            $shape = $i % 10;
            $expires = match (true) {
                ! $product->tracks_expiry => null,
                $shape < 2 => $today->copy()->subDays(1 + ($i % 20))->toDateString(),
                $shape < 4 => $today->copy()->addDays(1 + ($i % 6))->toDateString(),
                default => $today->copy()->addDays(30 + ($i % 300))->toDateString(),
            };

            $quantity = match (true) {
                $shape === 9 => 3.0,
                $shape === 8 => 1.0 + ($i % 2),
                default => 4.0 + ($i % 20),
            };

            $writer->receive($product, $location, $quantity, expiresAt: $expires);

            // Out of stock reached the honest way, through the ledger, so the history explains the
            // zero rather than it being an absence.
            if ($shape === 9) {
                $writer->consume($product, $location, $quantity);
            }

            // A second location for one in seven, so the per-location breakdown has products that
            // genuinely span two shelves and the location filter has something to narrow.
            if ($shape !== 9 && $i % 7 === 0) {
                $writer->transfer($product, $location, $locations[($i + 1) % $locations->count()], 1);
            }

            // A fractional total on some of the products that can express one, so the split figure
            // ("1 piece + 250 g") appears at volume rather than only on the curated cheese.
            if ($shape !== 9 && $hasContent && $i % 9 === 0) {
                $writer->consume($product, $location, 0.5);
            }
        }

        $this->command?->info('Seeded '.$count.' extra products for list, filter and search testing.');
    }
}
