<?php

declare(strict_types=1);

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
            Product::query()->with('stock')->orderBy('name')->get(),
        );
    }

    public function store(Request $request): ProductResource
    {
        $data = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'brand' => ['nullable', 'string', 'max:255'],
            // Unique within the tenant only, and enforced here rather than by a database index
            // because a partial unique index (only where `sku` is not null) is not portable to
            // sqlite, and because validation can say which product already holds the code.
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
            Product::query()->with('stock')->findOrFail($id),
        );
    }
}
