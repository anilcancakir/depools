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
            'content_unit' => ['nullable', 'string', 'max:16'],
            'par_level' => ['nullable', 'numeric', 'min:0'],
        ]);

        return new ProductResource(Product::create($data));
    }

    public function show(string $id): ProductResource
    {
        return new ProductResource(
            Product::query()->with(['stock', 'tags'])->findOrFail($id),
        );
    }
}
