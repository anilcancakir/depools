<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Resources\ProductResource;
use App\Models\Barcode;
use App\Models\Product;
use App\Models\ProductBarcode;
use App\Models\Scopes\TeamScope;
use App\Services\ProductListQuery;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Validation\Rule;

/**
 * Products.
 *
 * Tenancy is the model's job here too; see [LocationController] for why nothing in this file
 * mentions `team_id`.
 */
final class ProductController extends Controller
{
    /**
     * How many rows a page holds when the caller does not say.
     *
     * Thirty is roughly two phone screens of list, so the next page is already in flight before the
     * user reaches the bottom of this one.
     */
    private const PER_PAGE = 30;

    /**
     * One page of the tenant's products, narrowed by the filter the client sends.
     *
     * ### Cursor, not offset
     *
     * A stock list changes while it is being read: a count commits, a receipt lands, and every later
     * page shifts by one under an OFFSET. The reader then sees a row twice or never. A cursor is
     * keyed on the ordering columns instead, so an insert somewhere behind the reader cannot move
     * what is in front of them.
     *
     * **`id` after `name` is what makes the cursor sound, not tidiness.** A cursor built on `name`
     * alone cannot separate two products sharing one, so `where name > 'Süt'` skips the second `Süt`
     * and `>=` repeats the first. This catalog HAS duplicate names: the demo tenant holds two, and
     * the count screen already keys its figures by id for the same reason.
     *
     * ### Why the count is a second query
     *
     * A cursor paginator has no total by construction, which is most of why it is cheap. The filter
     * sheet previews how many rows a draft filter would match, so the number has to exist; it is a
     * COUNT over the same predicates rather than a second definition of them. One extra query per
     * request, over one tenant's catalog, which is what buys a filter that can say what it will do
     * before it does it.
     */
    public function index(Request $request): AnonymousResourceCollection
    {
        $criteria = $request->validate([
            // `ProductFilter.toMap()`'s keys, unchanged. That shape is already the one the
            // assistant's `search_products` tool speaks, so a second spelling here would be a
            // translation layer between two definitions of one filter.
            'query' => ['nullable', 'string', 'max:255'],
            'location_ids' => ['sometimes', 'array'],
            'location_ids.*' => ['uuid'],
            'category_ids' => ['sometimes', 'array'],
            'category_ids.*' => ['uuid'],
            'tags' => ['sometimes', 'array'],
            'tags.*' => ['string', 'max:64'],
            'brands' => ['sometimes', 'array'],
            'brands.*' => ['string', 'max:255'],
            'stock_state' => ['nullable', Rule::in(['out_of_stock', 'below_par', 'in_stock'])],
            'expiry' => ['nullable', Rule::in(['expired', 'expiring_soon'])],
            'sort' => ['nullable', Rule::in(ProductListQuery::SORTS)],
            'per_page' => ['nullable', 'integer', 'min:1', 'max:100'],
            'cursor' => ['nullable', 'string'],
        ]);

        // ONE reference date for the whole request. Two calls either side of midnight would count a
        // product as expired for the page and not for the total, which is the shape of bug that reads
        // as a flickering list rather than as a clock problem.
        $filter = new ProductListQuery($criteria, today());

        $page = $filter->apply(
            Product::query()
                ->with(['stock', 'tags'])
                // One aggregate for the whole page rather than a query per row. The count decides
                // which certainty tier the client is allowed to speak in, so a list without it can
                // only render the most cautious one for everything.
                ->withCount('movements'),
        )
            // The ordering moved INTO the filter object, because the cursor and the sort are one
            // decision: an aggregate sort has to select its own column for the cursor to be able to
            // read it, and only the thing that built the join can add that select.
            ->cursorPaginate($criteria['per_page'] ?? self::PER_PAGE)
            ->withQueryString();

        return ProductResource::collection($page)->additional([
            // A fresh builder, because the one above is spent. Same filter object, so the predicates
            // cannot drift between the page and its own count.
            'meta' => ['total' => $filter->apply(Product::query())->count()],
        ]);
    }

    public function store(Request $request): ProductResource
    {
        $data = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'brand' => ['nullable', 'string', 'max:255'],
            // Unique within the tenant only. The reason recorded here used to be that "a partial unique
            // index is not portable to sqlite", which stopped being true when D72 moved the suite onto
            // PostgreSQL: `products_team_sku_unique` now exists and is the real guarantee. This rule
            // stays because it is the only one of the two that can say WHICH product already holds the
            // code, and a 422 naming the conflict beats a 500 from a constraint.
            'sku' => ['nullable', 'string', 'max:64', Rule::unique('products', 'sku')
                ->where('team_id', $request->user()->current_team_id)
                ->whereNull('deleted_at')],
            'base_unit' => ['required', 'string', 'max:16'],
            'tracks_expiry' => ['boolean'],
            'default_shelf_life_days' => ['nullable', 'integer', 'min:1', 'max:3650'],
            'opened_shelf_life_days' => ['nullable', 'integer', 'min:1', 'max:365'],
            'content_amount' => ['nullable', 'numeric', 'min:0'],
            // **A content unit has to be FINER than the base unit, so it cannot be the same one.**
            // The base unit is what you count and the content is what one of them holds: a carton is
            // `piece` holding `1000 ml`. `base_unit: 'l'` with `content_unit: 'l'` says a litre
            // contains a litre, and the demo seeder shipped six products in exactly that shape. It
            // made the app look wrong where it was not: a 500 g pack read as "2 g" on the count sheet,
            // and the split-quantity field cannot work at all, because half of a base unit is then
            // half of the same unit rather than a count of smaller ones (D26).
            'content_unit' => ['nullable', 'string', 'max:16', 'different:base_unit'],
            'par_level' => ['nullable', 'numeric', 'min:0'],
        ]);

        return new ProductResource(Product::create($data));
    }

    /**
     * The tenant's product carrying a scanned barcode, or a 404.
     *
     * ### Why this is not the search endpoint with a different argument
     *
     * A barcode is an identity, not a search term, and the count screen needs three answers apart:
     * the product is here, the product is the tenant's but not on this shelf, and the tenant has no
     * such product. The list endpoint scopes by location, so the second and third both come back as an
     * empty page and the screen cannot tell a misplaced product from an unknown one. This answers about
     * the product alone and lets the client compare against the shelf it is counting.
     *
     * ### The 404 is about the LINK, not the barcode
     *
     * Barcode rows are global on purpose: one tenant's scan is what makes the next tenant's lookup
     * possible. So the row for a carton of milk is one an attacker can obtain by walking into a shop,
     * and finding it must say nothing about anybody's inventory. The answer comes from
     * `product_barcode`, which is a tenant table under the same scope as everything else, and a miss is
     * a 404 rather than a 403 because 403 would confirm the link exists.
     */
    public function byBarcode(Request $request): ProductResource
    {
        $data = $request->validate([
            // 128 because `barcodes.code` is `string(128)`, so anything longer could never have been
            // stored and therefore can never resolve. Accepting it would answer a 404 that means
            // "no such product" when the truth is "this API cannot hold that value", and those are
            // two different things for a client deciding whether to offer the user a draft product.
            'code' => ['required', 'string', 'max:128'],
            // Part of the identity for a non-GTIN label rather than a hint: the same characters as
            // Code128 and as a QR are two different labels. Absent for a GTIN, which needs no help.
            'symbology' => ['nullable', 'string', 'max:16'],
        ]);

        $barcode = Barcode::findForScan($data['code'], $data['symbology'] ?? null);

        // Two different misses, one answer. Nothing anywhere carries this code, or something does and
        // it is not this tenant's; telling those apart would leak the second one.
        abort_if($barcode === null, 404);

        // **Straight at the pivot, which is what the pivot was built for.** Its own migration says so:
        // "a scan asks which of MY products is this barcode, and that has to be one index lookup rather
        // than a join into products to find out whether the answer was even ours". A `whereHas` here
        // asks it the other way round, as an EXISTS correlated on `products.id`, so the planner starts
        // from the tenant's catalogue and probes the pivot per row. `unique(team_id, barcode_id)` is
        // exactly this pair and cannot be used at all without the team, because it leads on it.
        //
        // The team comes from the auth context, never from the request, which is the same source
        // `TeamScope` reads. And the scope is still the guarantee rather than this filter: the product
        // is fetched through a scoped query below, so a pivot row belonging to somebody else could not
        // produce a product even if this narrowing were wrong.
        $productId = ProductBarcode::query()
            ->where('team_id', TeamScope::currentTeamId())
            ->where('barcode_id', $barcode->getKey())
            ->value('product_id');

        abort_if($productId === null, 404);

        $product = Product::query()
            ->with(['stock', 'tags'])
            ->find($productId);

        abort_if($product === null, 404);

        return new ProductResource($product);
    }

    public function show(string $id): ProductResource
    {
        $product = Product::query()
            ->with(['stock', 'tags', 'lots', 'serials'])
            ->withCount('movements')
            ->findOrFail($id);

        // Hand each lot the product it already came from. `StockLot::bindingDate()` needs
        // `opened_shelf_life_days` to work out an opened lot's deadline, and without this it would
        // lazy-load the same product once per lot: a carton of milk with four lots is four identical
        // queries for a value already in memory. Eager-loading `lots.product` would fetch it once
        // instead of four times and still fetch a row we are holding.
        $product->lots->each(static fn ($lot) => $lot->setRelation('product', $product));

        return new ProductResource($product);
    }
}
