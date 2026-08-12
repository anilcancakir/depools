<?php

namespace Tests\Feature;

use App\Models\Location;
use App\Models\Product;
use App\Models\Team;
use App\Models\User;
use App\Services\StockLedger;
use App\Services\StockWriter;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * `GET /products` once it stopped answering the whole collection.
 *
 * Two things are being pinned here and they are not the same thing. The FILTER has to select the same
 * rows the client's own predicate used to select, because the screen and the badges are unchanged and
 * a server that disagrees with them shows a product under "expiring soon" with a green badge on it.
 * The CURSOR has to be stable, which is a property no single-page assertion can observe: a cursor
 * that skips or repeats looks perfect until you walk to the second page.
 */
final class ProductListFilterTest extends TestCase
{
    use RefreshDatabase;

    private Location $fridge;

    private Location $pantry;

    private StockWriter $writer;

    protected function setUp(): void
    {
        parent::setUp();

        $this->signIn('Birinci');

        $this->fridge = Location::create(['name' => 'Buzdolabı']);
        $this->pantry = Location::create(['name' => 'Kiler']);
        $this->writer = new StockWriter(new StockLedger);
    }

    /**
     * Signs a fresh user into their own team and returns them.
     */
    private function signIn(string $team): User
    {
        /** @var User $user */
        $user = User::factory()->createOne();
        $team = Team::create(['name' => $team, 'user_id' => $user->getKey()]);
        $user->forceFill(['current_team_id' => $team->getKey()])->save();
        $user->refresh();

        $this->actingAs($user, 'sanctum');

        return $user;
    }

    /**
     * @param  array<string, mixed>  $attributes
     */
    private function product(string $name, array $attributes = []): Product
    {
        return Product::create(array_merge(['name' => $name, 'base_unit' => 'adet'], $attributes));
    }

    /**
     * The ids the endpoint answers for these criteria, in order.
     *
     * @param  array<string, mixed>  $criteria
     * @return list<string>
     */
    private function ids(array $criteria = []): array
    {
        $response = $this->getJson('/api/v1/products?'.http_build_query($criteria));

        $response->assertOk();

        return array_column($response->json('data'), 'id');
    }

    public function test_a_page_is_capped_and_says_how_to_reach_the_next_one(): void
    {
        foreach (range(1, 7) as $i) {
            $this->product('Ürün '.$i);
        }

        $response = $this->getJson('/api/v1/products?per_page=3')->assertOk();

        $response->assertJsonCount(3, 'data');
        $this->assertNotNull($response->json('meta.next_cursor'));

        // The total is the whole filtered set rather than the page, which is what the filter sheet
        // previews. A cursor paginator has no total of its own, so this is the assertion that the
        // extra count query is actually wired and not silently absent.
        $this->assertSame(7, $response->json('meta.total'));
    }

    public function test_the_cursor_neither_skips_nor_repeats_a_row_when_names_collide(): void
    {
        // **Five products sharing one name**, which is the case a cursor on `name` alone cannot
        // survive: `where name > 'Süt'` steps over the other four and `>=` returns the same one
        // forever. This catalog really does hold duplicate names, so `id` is a tiebreaker rather
        // than a formality.
        for ($i = 0; $i < 5; $i++) {
            $this->product('Süt');
        }

        $seen = [];
        $cursor = null;
        $pages = 0;

        do {
            $query = ['per_page' => 2];

            if ($cursor !== null) {
                $query['cursor'] = $cursor;
            }

            $response = $this->getJson('/api/v1/products?'.http_build_query($query))->assertOk();

            $seen = array_merge($seen, array_column($response->json('data'), 'id'));
            $cursor = $response->json('meta.next_cursor');
            $pages++;
        } while ($cursor !== null && $pages < 10);

        $this->assertSame(5, count($seen), 'the walk saw a row twice or missed one');
        $this->assertSame(5, count(array_unique($seen)));
        $this->assertSame(Product::query()->orderBy('name')->orderBy('id')->pluck('id')->all(), $seen);
    }

    public function test_free_text_matches_the_fold_rather_than_the_spelling(): void
    {
        $milk = $this->product('Pınar Süt Tam Yağlı', ['brand' => 'Pınar']);
        $this->product('Zeytinyağı');

        // An ASCII keyboard reaches a Turkish name, which is what `name_normalized` is for.
        $this->assertSame([$milk->getKey()], $this->ids(['query' => 'pinar sut']));
        $this->assertSame([$milk->getKey()], $this->ids(['query' => 'PINAR']));
        $this->assertSame([], $this->ids(['query' => 'kahve']));
    }

    public function test_a_typed_wildcard_is_a_character_and_not_a_pattern(): void
    {
        $this->product('Süt');
        $percent = $this->product('%50 Kakao');

        // Unescaped, `%` would match every product and the filter would read as doing nothing.
        $this->assertSame([$percent->getKey()], $this->ids(['query' => '%']));
    }

    public function test_a_product_with_no_projection_row_is_the_out_of_stock_case(): void
    {
        $empty = $this->product('Kablo');
        $held = $this->product('Süt');
        $this->writer->receive($held, $this->fridge, 6);

        // `rebuildProductStock` deletes a pair once it holds nothing, so an absent row is the
        // ordinary empty shelf rather than a projection that failed to travel.
        $this->assertSame([$empty->getKey()], $this->ids(['stock_state' => 'out_of_stock']));
        $this->assertSame([$held->getKey()], $this->ids(['stock_state' => 'in_stock']));
    }

    public function test_below_target_needs_a_target_somebody_chose(): void
    {
        $low = $this->product('Matkap', ['par_level' => 5]);
        $this->writer->receive($low, $this->pantry, 2);

        // Same small quantity, no target declared. Without the null guard this would report as
        // running low too, and "below target" would stop meaning anything.
        $untargeted = $this->product('Vida');
        $this->writer->receive($untargeted, $this->pantry, 2);

        // Above its target, so not low.
        $stocked = $this->product('Tornavida', ['par_level' => 1]);
        $this->writer->receive($stocked, $this->pantry, 9);

        // At the target exactly, which counts: the client's predicate is `<=`.
        $atTarget = $this->product('Çekiç', ['par_level' => 2]);
        $this->writer->receive($atTarget, $this->pantry, 2);

        $this->assertEqualsCanonicalizing(
            [$low->getKey(), $atTarget->getKey()],
            $this->ids(['stock_state' => 'below_par']),
        );
    }

    public function test_the_quantity_is_summed_across_locations(): void
    {
        // Two shelves, three and three, against a target of five. Neither shelf alone is above the
        // target and the product is: an axis reading one row at a time would report it as low.
        $split = $this->product('Süt', ['par_level' => 5]);
        $this->writer->receive($split, $this->fridge, 3);
        $this->writer->receive($split, $this->pantry, 3);

        $this->assertSame([], $this->ids(['stock_state' => 'below_par']));
        $this->assertSame([$split->getKey()], $this->ids(['stock_state' => 'in_stock']));
    }

    public function test_expired_is_the_earliest_date_and_never_also_expiring_soon(): void
    {
        $today = Carbon::today();

        $gone = $this->product('Bal', ['tracks_expiry' => true, 'default_shelf_life_days' => 30]);
        $this->writer->receive($gone, $this->pantry, 1, expiresAt: $today->copy()->subDay()->toDateString());

        // A second lot that is perfectly fine. The badge shows the EARLIEST date, so the product
        // reads as expired on both sides; a filter answering "has any fresh lot" would disagree
        // with the row the user is looking at.
        $this->writer->receive($gone, $this->pantry, 1, expiresAt: $today->copy()->addDays(20)->toDateString());

        $this->assertSame([$gone->getKey()], $this->ids(['expiry' => 'expired']));
        $this->assertSame([], $this->ids(['expiry' => 'expiring_soon']));
    }

    public function test_the_warning_window_belongs_to_the_product_and_not_to_the_list(): void
    {
        $today = Carbon::today();
        $date = $today->copy()->addDays(3)->toDateString();

        // **Same date, two answers, and that is the whole point of a per-product window.** A tin
        // with a two year shelf life warns 60 days out, so three days is deep inside its window. A
        // five day carton warns one day out, so three days still leaves it 60% of its life. One
        // global number cannot be right for both, which is the decision `open-decisions.md` records.
        $tin = $this->product('Konserve', ['tracks_expiry' => true, 'default_shelf_life_days' => 730]);
        $this->writer->receive($tin, $this->pantry, 2, expiresAt: $date);

        $milk = $this->product('Süt', ['tracks_expiry' => true, 'default_shelf_life_days' => 5]);
        $this->writer->receive($milk, $this->fridge, 2, expiresAt: $date);

        $this->assertSame([$tin->getKey()], $this->ids(['expiry' => 'expiring_soon']));

        // And the window the client renders its badge from is the same number, travelling in the
        // payload rather than being recomputed in Dart.
        $windows = [];

        foreach ($this->getJson('/api/v1/products')->json('data') as $row) {
            $windows[$row['name']] = $row['expiry_threshold_days'];
        }

        $this->assertSame(60, $windows['Konserve']);
        $this->assertSame(1, $windows['Süt']);
    }

    public function test_an_undeclared_shelf_life_still_warns(): void
    {
        $today = Carbon::today();

        // No shelf life, but a date. Falling back to "never warn" would make the most common shape
        // in a real catalog invisible to the filter that exists for it.
        $unknown = $this->product('Peynir', ['tracks_expiry' => true]);
        $this->writer->receive($unknown, $this->fridge, 1, expiresAt: $today->copy()->addDays(5)->toDateString());

        $this->assertSame([$unknown->getKey()], $this->ids(['expiry' => 'expiring_soon']));
        $this->assertSame(7, $this->getJson('/api/v1/products')->json('data.0.expiry_threshold_days'));
    }

    public function test_a_location_narrows_to_what_is_on_that_shelf(): void
    {
        $inFridge = $this->product('Süt');
        $this->writer->receive($inFridge, $this->fridge, 2);

        $inPantry = $this->product('Pirinç');
        $this->writer->receive($inPantry, $this->pantry, 2);

        $this->assertSame([$inFridge->getKey()], $this->ids(['location_ids' => [$this->fridge->getKey()]]));
        $this->assertEqualsCanonicalizing(
            [$inFridge->getKey(), $inPantry->getKey()],
            $this->ids(['location_ids' => [$this->fridge->getKey(), $this->pantry->getKey()]]),
        );
    }

    public function test_a_tag_narrows_by_the_name_the_chip_renders(): void
    {
        $tagged = $this->product('Süt');
        $tagged->syncTags(['soğuk zincir']);

        $this->product('Vida');

        $this->assertSame([$tagged->getKey()], $this->ids(['tags' => ['soğuk zincir']]));
    }

    public function test_a_brand_narrows_exactly(): void
    {
        $pinar = $this->product('Süt', ['brand' => 'Pınar']);
        $this->product('Süt', ['brand' => 'Sütaş']);

        $this->assertSame([$pinar->getKey()], $this->ids(['brands' => ['Pınar']]));
    }

    public function test_two_axes_narrow_together(): void
    {
        $today = Carbon::today();

        // Below its target AND inside its window, which is the pair the chip row can now form.
        $both = $this->product('Süt', [
            'par_level' => 5,
            'tracks_expiry' => true,
            'default_shelf_life_days' => 30,
        ]);
        $this->writer->receive($both, $this->fridge, 2, expiresAt: $today->copy()->addDays(3)->toDateString());

        // Low, but nowhere near its date.
        $lowOnly = $this->product('Yoğurt', [
            'par_level' => 5,
            'tracks_expiry' => true,
            'default_shelf_life_days' => 30,
        ]);
        $this->writer->receive($lowOnly, $this->fridge, 2, expiresAt: $today->copy()->addDays(25)->toDateString());

        $this->assertSame(
            [$both->getKey()],
            $this->ids(['stock_state' => 'below_par', 'expiry' => 'expiring_soon']),
        );
    }

    public function test_a_filtered_list_still_only_holds_the_callers_own_rows(): void
    {
        $this->signIn('İkinci');
        $theirs = $this->product('Pınar Süt', ['brand' => 'Pınar']);
        $theirFridge = Location::create(['name' => 'Onların dolabı']);
        $this->writer->receive($theirs, $theirFridge, 2);

        $this->signIn('Birinci');
        $mine = $this->product('Pınar Süt', ['brand' => 'Pınar']);

        // Same name, same brand, and a filter that matches both. Tenancy is not a property of the
        // unfiltered list only: every axis has to be inside the scope, and the total too.
        $response = $this->getJson('/api/v1/products?query=pinar')->assertOk();

        $this->assertSame([$mine->getKey()], array_column($response->json('data'), 'id'));
        $this->assertSame(1, $response->json('meta.total'));
        $this->assertSame([], $this->ids(['location_ids' => [$theirFridge->getKey()]]));
    }

    public function test_a_page_costs_the_same_number_of_queries_however_many_rows_it_holds(): void
    {
        $today = Carbon::today();

        // A fresh tenant per measurement rather than emptying the first one. Deleting the products
        // between runs is refused by `stock_movements_product_id_foreign`, which is the ledger being
        // append-only doing its job, and under `RefreshDatabase` that refusal aborts the whole
        // transaction so every later assertion in the test fails for an unrelated reason.
        $count = function (int $products) use ($today): int {
            $this->signIn('Ölçüm '.$products);
            $shelf = Location::create(['name' => 'Raf']);

            for ($i = 1; $i <= $products; $i++) {
                $product = $this->product('Ürün '.$i, [
                    'tracks_expiry' => true,
                    // A different shelf life every few products, so the expiring-soon bucketing has
                    // several windows to group rather than one.
                    'default_shelf_life_days' => 5 + ($i % 4) * 30,
                    'par_level' => 5,
                ]);

                $product->syncTags(['etiket '.($i % 3)]);
                $this->writer->receive($product, $shelf, 2, expiresAt: $today->copy()->addDays($i)->toDateString());
            }

            DB::flushQueryLog();
            DB::enableQueryLog();

            $this->getJson('/api/v1/products?per_page=100&expiry=expiring_soon')->assertOk();

            $queries = count(DB::getQueryLog());
            DB::disableQueryLog();

            return $queries;
        };

        // **Equality rather than a magic ceiling.** The number itself will move the next time an eager
        // load is added, and pinning it would fail for a change that is fine. What must never change is
        // that it does not depend on the row count: the projection, the tags and the movement counts are
        // all one query each, so a page of forty costs what a page of four does. A per-row lazy load
        // would show up here as the only thing that can make these two differ.
        $this->assertSame($count(4), $count(40));
    }

    public function test_each_sort_orders_by_what_it_names_and_stays_stable(): void
    {
        $today = Carbon::today();

        // Deliberately one shared quantity and one shared date, because a tie is where a cursor
        // fails: without `products.id` after the sort column the walk steps over the second row.
        $b = $this->product('B ürün', ['tracks_expiry' => true, 'default_shelf_life_days' => 30]);
        $a = $this->product('A ürün', ['tracks_expiry' => true, 'default_shelf_life_days' => 30]);
        $c = $this->product('C ürün');

        $this->writer->receive($b, $this->fridge, 5, expiresAt: $today->copy()->addDays(2)->toDateString());
        $this->writer->receive($a, $this->fridge, 5, expiresAt: $today->copy()->addDays(9)->toDateString());

        $this->assertSame(
            [$a->getKey(), $b->getKey(), $c->getKey()],
            $this->ids(['sort' => 'name']),
            'the default orders by name',
        );

        // `c` holds nothing, so it has no projection row at all and the left join gives NULL. Least
        // first has to put it FIRST, which is what the coalesce is for: a NULL would sort last in
        // PostgreSQL ascending and the product most in need of buying would land at the bottom.
        $this->assertSame($c->getKey(), $this->ids(['sort' => 'quantity'])[0]);

        // Soonest first, and the one with no date last rather than first: no date is the opposite
        // of urgent.
        $this->assertSame(
            [$b->getKey(), $a->getKey(), $c->getKey()],
            $this->ids(['sort' => 'expiry']),
        );
    }

    public function test_a_sort_with_ties_still_walks_every_row_once(): void
    {
        // Five products with no stock at all, so every one of them sorts at the same quantity. This
        // is the case `products.id` exists for, and the one a single-page assertion cannot see.
        for ($i = 0; $i < 5; $i++) {
            $this->product('Ürün '.$i);
        }

        $seen = [];
        $cursor = null;
        $pages = 0;

        do {
            $query = ['sort' => 'quantity', 'per_page' => 2];

            if ($cursor !== null) {
                $query['cursor'] = $cursor;
            }

            $response = $this->getJson('/api/v1/products?'.http_build_query($query))->assertOk();

            $seen = array_merge($seen, array_column($response->json('data'), 'id'));
            $cursor = $response->json('meta.next_cursor');
            $pages++;
        } while ($cursor !== null && $pages < 10);

        $this->assertSame(5, count(array_unique($seen)), 'a tie made the cursor skip or repeat');
        $this->assertSame(5, count($seen));
    }

    public function test_recent_orders_by_when_a_product_last_changed(): void
    {
        $old = $this->product('Eski');
        $middle = $this->product('Orta');
        $newest = $this->product('Yeni');

        // Written explicitly rather than relying on creation order: three inserts inside one test can
        // land on the same millisecond, and a test that passes because the rows happened to be saved
        // in the right sequence is pinning the clock rather than the ORDER BY.
        $old->forceFill(['updated_at' => now()->subDays(3)])->saveQuietly();
        $middle->forceFill(['updated_at' => now()->subDay()])->saveQuietly();
        $newest->forceFill(['updated_at' => now()])->saveQuietly();

        $this->assertSame(
            [$newest->getKey(), $middle->getKey(), $old->getKey()],
            $this->ids(['sort' => 'recent']),
        );
    }

    public function test_recent_survives_a_tie_the_way_every_other_sort_does(): void
    {
        // Five products stamped with the SAME instant, which is the ordinary case for anything a
        // migration, an import or a seeder wrote in one pass. Without `products.id` after
        // `updated_at` the cursor cannot separate them.
        $stamp = now()->subHour();

        for ($i = 0; $i < 5; $i++) {
            $this->product('Ürün '.$i)->forceFill(['updated_at' => $stamp])->saveQuietly();
        }

        $seen = [];
        $cursor = null;
        $pages = 0;

        do {
            $query = ['sort' => 'recent', 'per_page' => 2];

            if ($cursor !== null) {
                $query['cursor'] = $cursor;
            }

            $response = $this->getJson('/api/v1/products?'.http_build_query($query))->assertOk();

            $seen = array_merge($seen, array_column($response->json('data'), 'id'));
            $cursor = $response->json('meta.next_cursor');
            $pages++;
        } while ($cursor !== null && $pages < 10);

        $this->assertSame(5, count(array_unique($seen)));
        $this->assertSame(5, count($seen));
    }

    public function test_an_unknown_sort_is_refused_rather_than_silently_ignored(): void
    {
        // A dropped sort answers in the default order and looks like the option did nothing.
        $this->getJson('/api/v1/products?sort=cheapest')->assertJsonValidationErrorFor('sort');
    }

    public function test_an_unknown_axis_value_is_refused_rather_than_ignored(): void
    {
        // A silently dropped filter is the worst answer available: the list comes back unnarrowed
        // and looks like the filter found everything.
        $this->getJson('/api/v1/products?stock_state=nonsense')->assertJsonValidationErrorFor('stock_state');
        $this->getJson('/api/v1/products?expiry=someday')->assertJsonValidationErrorFor('expiry');
        $this->getJson('/api/v1/products?per_page=500')->assertJsonValidationErrorFor('per_page');
        $this->getJson('/api/v1/products?location_ids[]=not-a-uuid')
            ->assertJsonValidationErrorFor('location_ids.0');
    }
}
