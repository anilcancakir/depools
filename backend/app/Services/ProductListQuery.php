<?php

namespace App\Services;

use App\Models\Barcode;
use App\Models\Product;
use Carbon\CarbonInterface;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Query\Builder as QueryBuilder;
use Illuminate\Database\Query\JoinClause;
use Illuminate\Support\Facades\DB;

/**
 * The stock list's seven filter axes, applied in the database rather than in the client.
 *
 * ### Why this exists at all
 *
 * The list used to answer the whole collection and the client filtered the rows it had. That works
 * exactly until the list is paginated, and then it is broken by construction: a filter over one page
 * of thirty can only ever find what that page already contained, so "expired" would report three
 * items on page one and a different three on page two. Pagination and client-side filtering cannot
 * both be true, so the predicates move here.
 *
 * The wire vocabulary is `ProductFilter.toMap()`'s, unchanged, because that shape is already shared
 * with the assistant's `search_products` tool. A second spelling on the HTTP boundary would be a
 * translation layer between two definitions of the same filter.
 *
 * ### One aggregate join, not five correlated subqueries
 *
 * Four of the axes ask about a product's total quantity or its earliest date, and both are sums over
 * `product_stock`. Asking per axis would put a correlated subquery in the WHERE clause for each one;
 * `stock_totals` computes both once and every axis then compares against a plain column.
 *
 * ### Where the arithmetic lives (D84, and Anılcan's rule)
 *
 * No calculation happens in SQL. The expiring-soon window is per product, derived from its own shelf
 * life, so the obvious implementation is `ROUND(shelf_life * 0.2)` inside the WHERE clause. Instead
 * PHP asks which shelf lives the tenant actually holds, computes one DATE per distinct window
 * through [Product::expiryThresholdFor], and hands those dates down as bindings. The database only
 * compares a column to a value; the formula exists once, in PHP, and the client reads the same
 * number out of the payload rather than recomputing it.
 */
final class ProductListQuery
{
    /**
     * @param  array<string, mixed>  $criteria  validated `ProductFilter.toMap()` keys
     */
    public function __construct(
        private readonly array $criteria,
        private readonly CarbonInterface $today,
    ) {}

    /**
     * Narrows [$query] by every axis the criteria carry.
     *
     * Takes and returns the builder rather than owning it, so the caller decides the ordering, the
     * eager loads and whether this run is the page or the count behind it.
     *
     * @param  Builder<Product>  $query
     * @return Builder<Product>
     */
    public function apply(Builder $query): Builder
    {
        // `products.*`, not `*`. The join below adds `product_id`, `total_quantity` and
        // `earliest_expires_at`, and a bare `select *` hydrates all three onto the model: a Product
        // would then answer to `earliest_expires_at`, which belongs to a lot, and to `product_id`,
        // which belongs to something pointing AT a product.
        //
        // **Only when nothing has selected yet, and that guard is load-bearing.** `withCount` adds its
        // `(select count(*) ...) as movements_count` to the select list, and qualifies `products.*`
        // itself while doing it. An unconditional `select('products.*')` here REPLACES the whole list
        // and takes the subquery with it, so `movements_count` silently disappears and every product
        // drops to the most cautious forecast tier. `InventoryApiTest` caught it as an undefined key.
        if ($query->getQuery()->columns === null) {
            $query->select('products.*');
        }

        $query->leftJoinSub(
            $this->stockTotals(),
            'stock_totals',
            // Joined on the tenant as well as on the product. The outer query is already scoped by
            // `TeamScope`, so this cannot widen the result; what it closes is a `product_stock` row
            // whose `team_id` disagrees with its product's. `StockWriter` always stamps it from the
            // product, and nothing in the schema forces that, so the join states it.
            function (JoinClause $join): void {
                $join->on('stock_totals.product_id', '=', 'products.id')
                    ->on('stock_totals.team_id', '=', 'products.team_id');
            },
        );

        $this->applyText($query);
        $this->applySets($query);
        $this->applyStockState($query);
        $this->applyExpiry($query);
        $this->applyOrder($query);

        return $query;
    }

    /**
     * The sort options a caller may name, and what each one answers.
     *
     * Four, and each maps to a DIFFERENT question, which is the test a sort option has to pass to
     * earn a place: find it by name, what do I need to buy, what do I need to use up, what just
     * moved. A fifth would either repeat one of those or answer something nobody asks.
     */
    public const SORTS = ['name', 'quantity', 'expiry', 'recent'];

    /**
     * Orders the page, and gives the cursor something unique to hold on to.
     *
     * ### Every order ends in `products.id`, and that is not tidiness
     *
     * A cursor is `WHERE (sort_column, id) > (?, ?)`. Without a unique tiebreaker two rows sharing a
     * sort value cannot be separated, so `>` steps over the second and `>=` returns the first
     * forever. `name` was already proven to need it (this catalogue holds duplicate names) and every
     * other option needs it MORE: a hundred products can share a quantity of zero.
     *
     * ### Why the aggregate sorts select their own column
     *
     * Laravel builds the cursor by reading the ordering column OFF THE MODEL, so ordering by
     * `stock_totals.total_quantity` while selecting only `products.*` gives it nothing to read and
     * the next page starts from the beginning. Selecting it under a name the model carries is what
     * makes the cursor able to encode it.
     *
     * `coalesce` is there for the same reason rather than as arithmetic: a product with no stock has
     * no projection row at all (`rebuildProductStock` deletes a pair once it holds nothing), so the
     * left join gives NULL, and a NULL in a cursor comparison is not orderable. Substituting a value
     * to sort BY is a query concern; nothing here derives a quantity or writes one down.
     *
     * @param  Builder<Product>  $query
     */
    private function applyOrder(Builder $query): void
    {
        switch ($this->criteria['sort'] ?? null) {
            case 'quantity':
                // Least first, because the question this answers is what to buy.
                $query->addSelect(
                    DB::raw('coalesce(stock_totals.total_quantity, 0) as sort_quantity'),
                )->orderBy('sort_quantity')->orderBy('products.id');
                break;

            case 'expiry':
                // Soonest first, and a product with no date sorts LAST rather than first: no date is
                // the opposite of urgent, and `ORDER BY ... NULLS LAST` cannot be used because the
                // cursor would then have to encode a NULL. The sentinel never leaves this clause: it
                // is not stored, not sent, and not shown.
                $query->addSelect(
                    DB::raw("coalesce(stock_totals.earliest_expires_at, '9999-12-31') as sort_expiry"),
                )->orderBy('sort_expiry')->orderBy('products.id');
                break;

            case 'recent':
                // What moved last, newest first. `updated_at` rather than the ledger's own clock,
                // because a rename is a change the user is looking for here too.
                $query->orderByDesc('products.updated_at')->orderByDesc('products.id');
                break;

            default:
                $query->orderBy('products.name')->orderBy('products.id');
        }
    }

    /**
     * Current quantity and earliest date per product, in one pass over the projection.
     */
    private function stockTotals(): QueryBuilder
    {
        return DB::table('product_stock')
            ->select('product_id', 'team_id')
            ->selectRaw('sum(quantity) as total_quantity')
            ->selectRaw('min(earliest_expires_at) as earliest_expires_at')
            ->groupBy('product_id', 'team_id');
    }

    /**
     * Free text over the folded name, the brand and the SKU.
     *
     * `name_normalized` is the fold `NormalisesName` writes and `products_name_normalized_trgm`
     * indexes, so a user typing `pinar` finds `Pınar` and the GIN index serves the `LIKE`. A
     * substring match rather than the `%` similarity operator the receipt cascade uses: `su` is not
     * SIMILAR to `Pınar Süt Tam Yağlı 1 lt` by any threshold, and search-as-you-type is a prefix of
     * a word rather than a whole line to match.
     *
     * **Brand and SKU are matched case-insensitively but not diacritic-insensitively**, because
     * neither column carries a fold. So `pinar` reaches the brand `Pınar` only through the product
     * name, which in practice contains it. Closing that properly means a folded `brand` column with
     * its own drift check (the D88 shape), which is a schema change and not this one.
     *
     * @param  Builder<Product>  $query
     */
    private function applyText(Builder $query): void
    {
        $needle = trim((string) ($this->criteria['query'] ?? ''));

        if ($needle === '') {
            return;
        }

        $folded = '%'.$this->escapeLike((string) Product::normaliseName($needle)).'%';
        $raw = '%'.$this->escapeLike($needle).'%';

        // Resolved once, outside the closure, so a name search costs nothing extra: this only runs a
        // query when the needle could be a barcode at all, and returns null the moment it cannot.
        $barcode = Barcode::findForScan($needle);

        $query->where(function (Builder $q) use ($folded, $raw, $barcode): void {
            $q->where('products.name_normalized', 'like', $folded)
                ->orWhere('products.brand', 'ilike', $raw)
                ->orWhere('products.sku', 'ilike', $raw);

            // **A barcode matches exactly, while everything beside it matches partially, and that
            // asymmetry is deliberate.** A desktop barcode reader is an HID keyboard that types the
            // whole code into whichever field has focus, so the needle is complete by construction. A
            // partial match would answer `869` with every Turkish product in the catalogue, which is
            // noise dressed as a search result.
            //
            // No tenant filter on the pivot, and it is not missing: the outer query is already scoped
            // to this tenant's products, and `Product::linkBarcode` stamps the pivot with the
            // product's own team, so the two cannot name different tenants. A raw attach could not
            // either, because the column refuses the null it would write.
            if ($barcode !== null) {
                $q->orWhereHas(
                    'barcodes',
                    static fn (Builder $b): Builder => $b->whereKey($barcode->getKey()),
                );
            }
        });
    }

    /**
     * Escapes the wildcards a user can type.
     *
     * Without this a search for `%` matches every product and reads as a filter that does nothing.
     * PostgreSQL's default LIKE escape character is the backslash, so no `ESCAPE` clause is needed.
     */
    private function escapeLike(string $value): string
    {
        return str_replace(['\\', '%', '_'], ['\\\\', '\%', '\_'], $value);
    }

    /**
     * The four multi-select axes.
     *
     * **A location matches directly rather than including its descendants.** The filter's own
     * documentation says a parent implies its children, and the client's predicate has never done
     * that either, so both sides agree today. Expanding the tree here alone would make the server
     * answer a different question from the one the sheet's count previews, which is worse than the
     * gap; it moves when both sides move.
     *
     * @param  Builder<Product>  $query
     */
    private function applySets(Builder $query): void
    {
        $locations = $this->strings('location_ids');

        if ($locations !== []) {
            $query->whereExists(
                fn (QueryBuilder $q): QueryBuilder => $q->from('product_stock')
                    ->whereColumn('product_stock.product_id', 'products.id')
                    ->whereIn('product_stock.location_id', $locations),
            );
        }

        $categories = $this->strings('category_ids');

        if ($categories !== []) {
            $query->whereIn('products.product_category_id', $categories);
        }

        $brands = $this->strings('brands');

        if ($brands !== []) {
            $query->whereIn('products.brand', $brands);
        }

        $tags = $this->strings('tags');

        if ($tags !== []) {
            // By NAME, which is what the payload sends and what the chip renders. `ProductResource`
            // records why a tag travels as a name rather than as an id.
            $query->whereHas('tags', fn (Builder $q): Builder => $q->whereIn('tags.name', $tags));
        }
    }

    /**
     * How much is on hand, relative to the target the user set.
     *
     * `rebuildProductStock` deletes a pair once it holds nothing, so a product with no row at all is
     * the ordinary out-of-stock case rather than a missing projection. The `<= 0` half is unreachable
     * through `StockWriter` (a CHECK refuses a negative) and costs nothing to state.
     *
     * @param  Builder<Product>  $query
     */
    private function applyStockState(Builder $query): void
    {
        switch ($this->criteria['stock_state'] ?? null) {
            case 'out_of_stock':
                $query->where(
                    fn (Builder $q): Builder => $q->whereNull('stock_totals.total_quantity')
                        ->orWhere('stock_totals.total_quantity', '<=', 0),
                );
                break;

            case 'in_stock':
                // Anything on hand, matching the client's own predicate. The enum's name suggests
                // "above target", and its implementation has always been "not zero"; the two
                // disagreeing across the wire would be worse than the name being loose.
                $query->where('stock_totals.total_quantity', '>', 0);
                break;

            case 'below_par':
                // A target the user actually chose. Without the null guard every product holding a
                // little would report as running low, and "below target" has to mean something
                // somebody decided.
                $query->whereNotNull('products.par_level')
                    ->where('stock_totals.total_quantity', '>', 0)
                    ->whereColumn('stock_totals.total_quantity', '<=', 'products.par_level');
                break;
        }
    }

    /**
     * Past its date, or inside its own warning window.
     *
     * @param  Builder<Product>  $query
     */
    private function applyExpiry(Builder $query): void
    {
        $axis = $this->criteria['expiry'] ?? null;

        if ($axis === null) {
            return;
        }

        $today = $this->today->toDateString();

        if ($axis === 'expired') {
            $query->whereNotNull('stock_totals.earliest_expires_at')
                ->where('stock_totals.earliest_expires_at', '<', $today);

            return;
        }

        // Already expired is NOT expiring soon: they are different situations and the user picks one
        // of them. The earliest date is the one the badge shows, so a product with one expired lot
        // and one fresh lot reads as expired on both sides.
        $query->whereNotNull('stock_totals.earliest_expires_at')
            ->where('stock_totals.earliest_expires_at', '>=', $today)
            ->where(function (Builder $outer): void {
                foreach ($this->windowsByShelfLife() as $days => $lives) {
                    $outer->orWhere(function (Builder $q) use ($days, $lives): void {
                        $this->whereShelfLifeIn($q, $lives);

                        $q->where(
                            'stock_totals.earliest_expires_at',
                            '<=',
                            $this->today->copy()->addDays($days)->toDateString(),
                        );
                    });
                }
            });
    }

    /**
     * The tenant's distinct shelf lives, grouped by the window they produce.
     *
     * Grouped rather than listed one product at a time, and grouped by the WINDOW rather than by the
     * shelf life, because the formula collapses: everything above 300 days caps at 60, and a fifth
     * of 5 and a fifth of 7 both round to 1. A demo tenant with a hundred products holds a handful
     * of distinct windows, so the OR branch count is that handful and not the row count.
     *
     * Scoped, so it reads this tenant's shelf lives. Under `TeamScope` outside a request it would
     * read nothing, and the filter would then match nothing rather than leaking; the endpoint is
     * behind `auth:sanctum`, which is what makes that unreachable here.
     *
     * @return array<int, list<int|null>> window in days => the shelf lives that produce it
     */
    private function windowsByShelfLife(): array
    {
        $windows = [];

        foreach (Product::query()->distinct()->pluck('default_shelf_life_days') as $life) {
            $life = $life === null ? null : (int) $life;

            $windows[Product::expiryThresholdFor($life)][] = $life;
        }

        return $windows;
    }

    /**
     * `default_shelf_life_days IN (...)`, with the undeclared case included when it belongs.
     *
     * Null is a shelf life like any other here: it produces the fallback window rather than no
     * warning, so it has to be selectable, and `whereIn` alone cannot express it.
     *
     * @param  Builder<Product>  $query
     * @param  list<int|null>  $lives
     */
    private function whereShelfLifeIn(Builder $query, array $lives): void
    {
        $declared = array_values(array_filter($lives, static fn (?int $life): bool => $life !== null));
        $undeclared = in_array(null, $lives, true);

        $query->where(function (Builder $q) use ($declared, $undeclared): void {
            if ($declared !== []) {
                $q->whereIn('products.default_shelf_life_days', $declared);
            }

            if ($undeclared) {
                $q->orWhereNull('products.default_shelf_life_days');
            }
        });
    }

    /**
     * One criteria key as a list of non-empty strings.
     *
     * @return list<string>
     */
    private function strings(string $key): array
    {
        $raw = $this->criteria[$key] ?? null;

        if (! is_array($raw)) {
            return [];
        }

        $out = [];

        foreach ($raw as $value) {
            if (is_string($value) && $value !== '') {
                $out[] = $value;
            }
        }

        return array_values(array_unique($out));
    }
}
