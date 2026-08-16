<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Resources\LocationResource;
use App\Http\Resources\ProductResource;
use App\Models\Location;
use App\Models\Product;
use App\Services\ProductListQuery;
use Illuminate\Database\Eloquent\Collection;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;

/**
 * One box, two kinds of answer.
 *
 * ### Why this is not two calls the client makes itself
 *
 * The screen's value is that ONE field answers both "where is the paprika" and "what is in the
 * pantry". Two requests that can disagree about a spinner is how that stops feeling like one box:
 * the products land, the locations land a beat later, and the "no match" state flickers in between
 * because half the answer had arrived.
 *
 * ### The product half reuses the list's own query
 *
 * `ProductListQuery` already implements what "matching" means for a product, including the `%` and
 * `_` escaping and the normalised-name fold the resolution cascade depends on. A second definition
 * here would be a second thing to keep in step, and the first divergence would be silent: two
 * screens answering the same typed word differently.
 *
 * ### The location half searches the PATH
 *
 * Not the leaf name. A user describes where something is by the route to it, so "kiler raf" has to
 * find `Kiler › Raf 1`, and the client's own predicate has always worked that way.
 */
final class SearchController extends Controller
{
    /**
     * How many of each kind one search answers.
     *
     * The screen shows a section per kind and a user refines rather than scrolls: a query matching
     * forty products is a query worth narrowing, not a page worth paginating. Small enough that both
     * halves plus their rows stay one modest response.
     */
    private const LIMIT = 20;

    public function __invoke(Request $request): JsonResponse
    {
        $data = $request->validate([
            // The same bound the product list puts on its own query, so a string one screen accepts
            // is never refused by the other.
            'q' => ['required', 'string', 'max:255'],
        ]);

        $needle = trim($data['q']);

        // **An empty query answers nothing rather than everything.** The screen renders its "start
        // typing" state for that, and a blank search that returned the whole catalogue would be the
        // most expensive request in the app fired by a stray keystroke.
        if ($needle === '') {
            return response()->json(['data' => ['products' => [], 'locations' => []]]);
        }

        $filter = new ProductListQuery(['query' => $needle], Carbon::today());

        $products = $filter->apply(
            Product::query()->with(['stock', 'tags', 'unit', 'primaryImage', 'forecast'])->withCount('movements'),
        )->limit(self::LIMIT)->get();

        return response()->json([
            'data' => [
                'products' => ProductResource::collection($products),
                'locations' => LocationResource::collection($this->locations($needle)),
            ],
        ]);
    }

    /**
     * Locations whose path contains the query.
     *
     * The PATH rather than the name, which is the client's own predicate and the reason a user can
     * type the route rather than the leaf: "kiler raf" finds `Kiler › Raf 1`.
     *
     * **`full_path` is an accessor, not a column**, and reaching for it in SQL is a 500 rather than
     * a wrong answer: it is derived in PHP from the stored `path`, which joins with `/`. So the
     * predicate normalises that separator to a space, or every multi-word query would miss the one
     * thing it was typed to find.
     *
     * The `replace` costs the index, which is a real trade and a cheap one here: a tenant has tens
     * of locations, the tree screen loads all of them in one request already, and the alternative is
     * a second stored column that has to be kept true.
     *
     * **The needle is escaped**, because `%` and `_` are LIKE wildcards and this one comes from a
     * search box: unescaped, a single `%` would answer every location the tenant has. The same hole
     * was measured on the icon search, where `%` alone returned all 4,185 rows.
     *
     * @return Collection<int, Location>
     */
    private function locations(string $needle)
    {
        $escaped = str_replace(['\\', '%', '_'], ['\\\\', '\%', '\_'], mb_strtolower($needle));

        return Location::query()
            ->whereRaw("lower(replace(path, '/', ' ')) like ?", ['%'.$escaped.'%'])
            ->withCount('stock')
            ->orderBy('path')
            ->limit(self::LIMIT)
            ->get();
    }
}
