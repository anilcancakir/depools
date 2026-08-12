<?php

namespace Database\Seeders;

use App\Enums\MovementReason;
use App\Models\Location;
use App\Models\Product;
use App\Models\Scopes\TeamScope;
use App\Services\StockWriter;
use Illuminate\Database\Seeder;
use Illuminate\Support\Carbon;
use Illuminate\Support\Collection;
use RuntimeException;

/**
 * A demo inventory chosen to make the screens judgeable, not to look plausible.
 *
 * Random data cannot do this job. Every status the design defines needs at least one row or the
 * badge that renders it has never been seen, and several layout rules in `.claude/rules/design.md`
 * were found by a row that happened to be awkward. So each product below is here for a reason and
 * the reason is in the comment beside it: a name long enough to truncate, a name carrying `ı` and
 * `Ş` so the `latin-ext` font subset is exercised, a product with no expiry so the reserved trailing
 * column is visible as empty rather than absent, and a quantity in the thousands so the tabular
 * alignment a monospace was chosen for has something to align.
 *
 * ### Stock is received through the writer, never inserted
 *
 * Every movement below goes through [StockWriter], so lots, the projection and `remaining_quantity`
 * are all produced by the same code a request runs. That is what makes this fixture worth trusting:
 * `DemoSeederTest` seeds and then runs the consistency sweep, and an empty sweep is the proof that
 * nothing here took a shortcut. Inserting rows directly would produce data that looks right and
 * disagrees with the ledger, which is the exact failure D81 exists to prevent.
 */
class DemoInventorySeeder extends Seeder
{
    public function run(): void
    {
        // This class is reachable on its own through `db:seed --class=DemoInventorySeeder`, which
        // skips [DatabaseSeeder] and therefore both of its guards. With no tenant resolved,
        // `BelongsToTeam` stamps a null `team_id` and the first insert then violates the NOT NULL on
        // `locations.team_id`, so the real failure is `SQLSTATE[23502]` naming a column rather than
        // anything about seeding. The guard exists to say WHY in a sentence, not to prevent a silent
        // write: the database already refuses that. Each entry point carries its own, because
        // trusting the other one is what makes a second entry point dangerous.
        if (! app()->environment(['local', 'testing'])) {
            throw new RuntimeException('The demo seeder only runs in local or testing.');
        }

        // The team, not the user. `TeamScope::currentTeamId()` reads `current_team_id` off the
        // authenticated user, so a logged-in user who has none resolves to null just like no user at
        // all, and the rows are stamped null either way. Guarding on `Auth::id()` would have looked
        // like a guard and let that case through.
        if (TeamScope::currentTeamId() === null) {
            throw new RuntimeException(
                'No current team resolved, so the first insert would fail on the NOT NULL on '
                .'locations.team_id. Run `db:seed` rather than this class alone, and let '
                .'DatabaseSeeder authenticate the demo user and set its current team first.',
            );
        }

        if (Product::query()->exists()) {
            $this->command?->warn('The demo team already has products; skipping. Reset with migrate:fresh --seed.');

            return;
        }

        $locations = $this->locations();
        $products = $this->products();
        $writer = app(StockWriter::class);
        $today = Carbon::today();

        // Plenty on hand and above its target: the ordinary case, and the one every other row is
        // read against.
        $writer->receive($products['milk'], $locations['fridge'], 8, expiresAt: $today->copy()->addDays(6)->toDateString());

        // Expires inside the warning window, so the `expiring` badge has a row.
        $writer->receive($products['cheese'], $locations['fridge'], 2, expiresAt: $today->copy()->addDays(3)->toDateString());

        // Already past its date. Seeded deliberately in the past rather than waiting for time to
        // pass, because a demo that only shows `expired` next week is not a fixture.
        $writer->receive($products['eggs'], $locations['fridge'], 12, expiresAt: $today->copy()->subDays(2)->toDateString());

        // Two lots of one product with different dates, which is the whole reason expiry belongs to
        // a lot: FEFO has to pick between these two and the screen has to show both.
        $writer->receive($products['lettuce'], $locations['fridge'], 2, expiresAt: $today->copy()->addDays(2)->toDateString());
        $writer->receive($products['lettuce'], $locations['fridge'], 3, expiresAt: $today->copy()->addDays(5)->toDateString());
        // One of them spoiled. `waste` is its own reason rather than a note on a consumption,
        // because waste percentage is a number the product promises to report.
        $writer->consume($products['lettuce'], $locations['fridge'], 1, MovementReason::Waste);

        // Long shelf life, no drama: the row that should look calm next to the ones that do not.
        $writer->receive($products['oliveOil'], $locations['pantry'], 3, expiresAt: $today->copy()->addDays(400)->toDateString());

        // No expiry at all. The lot still exists, carrying a null date, which is why there is one
        // shape of inbound stock rather than two.
        $writer->receive($products['sugar'], $locations['pantry'], 4);

        // Below its reorder point, so `low-stock` has a row that is genuinely low rather than empty.
        $writer->receive($products['tablets'], $locations['storeroom'], 6);

        // Received and then fully consumed: `out-of-stock` reached the honest way, through the
        // ledger, so the movement history explains the zero instead of it being an absence.
        $writer->receive($products['coffee'], $locations['pantry'], 2);
        $writer->consume($products['coffee'], $locations['pantry'], 2);

        // Four figures, so the monospace column has something worth aligning.
        $writer->receive($products['napkins'], $locations['shelfA'], 1240);

        // One product in two places, then moved between them. A transfer is a PAIR of movements, so
        // this is also the row that proves the per-location breakdown adds up to the total.
        $writer->receive($products['sunflowerOil'], $locations['storeroom'], 6, expiresAt: $today->copy()->addDays(200)->toDateString());
        $writer->transfer($products['sunflowerOil'], $locations['storeroom'], $locations['pantry'], 2);

        // The espresso machine gets NO stock, and that is the point. `StockWriter::receive` refuses a
        // serial-tracked product, because its quantity is the count of its serials and a lot would be
        // a second, disagreeing answer. It sits here as the row that exercises that branch.

        $this->command?->info(
            'Seeded '.$products->count().' products across '.count($locations).' locations, '
            .'through StockWriter.',
        );
    }

    /**
     * A two-root hierarchy, deep enough that `path` and `depth` are doing real work.
     *
     * @return array<string, Location>
     */
    private function locations(): array
    {
        $kitchen = Location::create(['name' => 'Kitchen']);
        $storeroom = Location::create(['name' => 'Storeroom']);

        return [
            'kitchen' => $kitchen,
            'fridge' => Location::create(['name' => 'Fridge', 'parent_location_id' => $kitchen->getKey()]),
            'freezer' => Location::create(['name' => 'Freezer', 'parent_location_id' => $kitchen->getKey()]),
            'pantry' => Location::create(['name' => 'Pantry', 'parent_location_id' => $kitchen->getKey()]),
            'storeroom' => $storeroom,
            'shelfA' => Location::create(['name' => 'Shelf A', 'parent_location_id' => $storeroom->getKey()]),
        ];
    }

    /**
     * @return Collection<string, Product>
     */
    private function products(): Collection
    {
        return collect($this->definitions())->map(
            static fn (array $attributes): Product => Product::create($attributes),
        );
    }

    /**
     * @return array<string, array<string, mixed>>
     */
    private function definitions(): array
    {
        return [
            // **The base unit is what you COUNT, and the content is what one of them holds.** Six
            // products here declared the base unit as the content measure and then a content of the
            // same unit: `base_unit: 'l'` with `content_amount: 1, content_unit: 'l'`, which says a
            // litre contains a litre. Anılcan caught it on the count sheet, where the cheese read
            // "2 g" for two 500 g packs and the left field of a split quantity has to be the
            // countable one: "1 pack + 250 g", never "2 g + 250 g".
            //
            // It also made the app look wrong where it was not: the stock list said "3 ml" for three
            // bottles, and `CountLine.hasFinerContent` correctly refused to split a quantity whose
            // content unit was its own base unit, so the milk lost its opened-amount field.
            'milk' => [
                'name' => 'Whole Milk 1 L',
                'brand' => 'Meadow',
                'base_unit' => 'piece',
                'tracks_expiry' => true,
                'default_shelf_life_days' => 7,
                'opened_shelf_life_days' => 3,
                // Millilitres rather than `1 l`, so an opened carton has something finer to be
                // measured in. That is the whole point of the second field (D26).
                'content_amount' => 1000,
                'content_unit' => 'ml',
                'par_level' => 6,
                'reorder_point' => 2,
            ],
            // Carries `ı`, which ships in the base latin subset, next to a name below that carries
            // `Ş` from `latin-ext`. Between them they fail visibly if only one subset is requested,
            // which DESIGN.md warns looks like a font-fallback glitch rather than a missing glyph.
            'cheese' => [
                'name' => 'Pınar Süzme Peynir 500 g',
                'brand' => 'Pınar',
                'base_unit' => 'piece',
                'tracks_expiry' => true,
                'default_shelf_life_days' => 21,
                'content_amount' => 500,
                'content_unit' => 'g',
                'par_level' => 2,
            ],
            // 52 characters. A name in a list row is the one thing allowed to ellipsise, and this is
            // the row that shows whether it does or whether it overflows instead.
            'oliveOil' => [
                'name' => 'Extra Virgin Olive Oil, Cold Pressed, 750 ml Bottle',
                'base_unit' => 'piece',
                'tracks_expiry' => true,
                'default_shelf_life_days' => 540,
                'content_amount' => 750,
                'content_unit' => 'ml',
                'par_level' => 2,
            ],
            'sugar' => [
                'name' => 'Şeker (Toz) 1 kg',
                'base_unit' => 'piece',
                // No expiry, so the trailing date column has to be RESERVED and empty on this row
                // rather than absent, or every field beside it shifts.
                'tracks_expiry' => false,
                'content_amount' => 1000,
                'content_unit' => 'g',
                'par_level' => 2,
            ],
            'eggs' => [
                'name' => 'Free Range Eggs',
                'base_unit' => 'piece',
                'tracks_expiry' => true,
                'default_shelf_life_days' => 21,
                'par_level' => 30,
                'reorder_point' => 12,
            ],
            'tablets' => [
                'name' => 'Dishwasher Tablets',
                'base_unit' => 'piece',
                'tracks_expiry' => false,
                'par_level' => 20,
                'reorder_point' => 10,
            ],
            'coffee' => [
                'name' => 'Ground Coffee 250 g',
                'brand' => 'Kronotrop',
                'base_unit' => 'piece',
                'tracks_expiry' => true,
                'default_shelf_life_days' => 180,
                'opened_shelf_life_days' => 21,
                'content_amount' => 250,
                'content_unit' => 'g',
                'par_level' => 1,
            ],
            'lettuce' => [
                'name' => 'Iceberg Lettuce',
                'base_unit' => 'piece',
                'tracks_expiry' => true,
                'default_shelf_life_days' => 6,
                'par_level' => 4,
            ],
            'napkins' => [
                'name' => 'Paper Napkins',
                'base_unit' => 'piece',
                'tracks_expiry' => false,
                'par_level' => 500,
            ],
            'sunflowerOil' => [
                'name' => 'Sunflower Oil 1 L',
                'base_unit' => 'piece',
                'tracks_expiry' => true,
                'default_shelf_life_days' => 365,
                'content_amount' => 1000,
                'content_unit' => 'ml',
                'par_level' => 4,
            ],
            // Serial-tracked, so it never gets a lot. See the note in `run()`.
            'espressoMachine' => [
                'name' => 'Espresso Machine',
                'brand' => 'Rancilio',
                'base_unit' => 'piece',
                'tracks_expiry' => false,
                'tracking_mode' => 'serial',
            ],
        ];
    }
}
