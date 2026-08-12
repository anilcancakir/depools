<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Resources\ProductResource;
use App\Models\Product;
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
    public function index(): AnonymousResourceCollection
    {
        return ProductResource::collection(
            Product::query()
                ->with(['stock', 'tags'])
                // One aggregate for the whole page rather than a query per row. The count decides
                // which certainty tier the client is allowed to speak in, so a list without it can
                // only render the most cautious one for everything.
                ->withCount('movements')
                ->orderBy('name')
                ->get(),
        );
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
