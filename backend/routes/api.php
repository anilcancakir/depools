<?php

declare(strict_types=1);

use App\Http\Controllers\Api\V1\LocationController;
use App\Http\Controllers\Api\V1\ProductController;
use App\Http\Controllers\Api\V1\StockController;
use Illuminate\Support\Facades\Route;

/*
|--------------------------------------------------------------------------
| Inventory API, v1
|--------------------------------------------------------------------------
|
| The Flutter client's contract. Every route is behind `auth:sanctum`, and that is not only about
| authentication: the tenant scope resolves `team_id` from the authenticated user, so an unguarded
| route would not leak another tenant's rows, it would return NOTHING and look like a broken
| feature. Failing closed is the right default and a guard is still required.
|
| Paths are English and plural here while the app's own URLs are Turkish. A screen's URL is read by
| the person using the product; an API path is read by whoever maintains the client, and mixing the
| two vocabularies inside one codebase costs more than it buys.
|
| No route accepts a team identifier in any form. `data-model.md`'s first tenancy rule is that
| `team_id` comes from the auth context only, and the surest way to keep that true is for the
| parameter not to exist.
*/

Route::middleware('auth:sanctum')->prefix('v1')->group(function (): void {
    Route::apiResource('locations', LocationController::class)->only(['index', 'store', 'show']);
    Route::apiResource('products', ProductController::class)->only(['index', 'store', 'show']);

    // Stock is not a resource with an id: it is a set of things that HAPPEN, and each one appends
    // to the ledger. Modelling these as `PATCH /products/{id}` would invite the client to think it
    // is setting a quantity, which is the exact mental model the ledger exists to replace.
    Route::prefix('stock')->group(function (): void {
        Route::post('receive', [StockController::class, 'receive']);
        Route::post('consume', [StockController::class, 'consume']);
        Route::post('transfer', [StockController::class, 'transfer']);
    });
});
