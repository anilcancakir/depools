<?php

use App\Http\Controllers\Api\V1\BarcodeController;
use App\Http\Controllers\Api\V1\LocationController;
use App\Http\Controllers\Api\V1\ProductController;
use App\Http\Controllers\Api\V1\ProductImageController;
use App\Http\Controllers\Api\V1\StockController;
use App\Http\Controllers\Api\V1\UnitController;
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

    // The vocabulary a client offers in a picker, and the one deliberate way a tenant extends it. No
    // update and no delete: a unit with products counted in it is what every delta in their ledger is
    // denominated in, so the foreign key is `restrictOnDelete` and a rename would reinterpret history.
    Route::get('units', [UnitController::class, 'index']);
    Route::post('units', [UnitController::class, 'store']);
    // **Before the resource, or `by-barcode` is read as a product id.** `products/{id}` matches any
    // segment, so declared after it this route never runs and the request dies in PostgreSQL instead,
    // as `invalid input syntax for type uuid: "by-barcode"`. Found by writing the test first.
    //
    // The code travels as a query parameter rather than a path segment because a non-GTIN label can be
    // arbitrary text (a QR carrying a URL), which does not belong in a path.
    Route::get('products/by-barcode', [ProductController::class, 'byBarcode']);

    // **A different question from `products/by-barcode`, which is why it is a different route.**
    // That one answers "is this MY product", which a count screen needs: a hit is a row to count.
    // This runs the resolution cascade and answers "what is this thing", which a scan screen needs,
    // and may legitimately return a product the tenant does not own. Folding them would let the
    // count screen offer to count somebody else's catalogue entry.
    Route::get('barcode/resolve', [BarcodeController::class, 'resolve']);

    Route::apiResource('products', ProductController::class)->only(['index', 'store', 'show']);

    // The gallery, nested because a picture has no meaning away from its product. Both ids resolve
    // under `TeamScope`, so another tenant's product and another tenant's picture are each a 404.
    //
    // No `index`: `GET products/{id}` already carries the gallery, and a screen that has the product
    // has its pictures. A second route answering the same question is a second thing to keep in step.
    Route::post('products/{product}/images', [ProductImageController::class, 'store']);
    Route::patch('products/{product}/images/{image}', [ProductImageController::class, 'update']);
    Route::delete('products/{product}/images/{image}', [ProductImageController::class, 'destroy']);

    // Stock is not a resource with an id: it is a set of things that HAPPEN, and each one appends
    // to the ledger. Modelling these as `PATCH /products/{id}` would invite the client to think it
    // is setting a quantity, which is the exact mental model the ledger exists to replace.
    Route::prefix('stock')->group(function (): void {
        // A GET among the posts, because it answers a question rather than appending anything.
        Route::get('recent-receiving-locations', [StockController::class, 'recentReceivingLocations']);

        Route::post('receive', [StockController::class, 'receive']);

        // **Before nothing and after nothing, but it is not `receive` with a list.** That one takes a
        // product the tenant already owns; this one takes a scan batch, which is mostly products the
        // catalogue named and the tenant has never held. Folding them would put product CREATION
        // behind a single-movement endpoint.
        Route::post('receive-batch', [StockController::class, 'receiveBatch']);
        Route::post('consume', [StockController::class, 'consume']);
        Route::post('transfer', [StockController::class, 'transfer']);

        // A count is the fourth thing that happens, and the only one that states an ABSOLUTE: the
        // client sends what is on the shelf and the server derives the difference. It takes a set of
        // lines rather than one product because a count is scoped to a location and a person counts a
        // whole shelf in one pass, so committing row by row would leave a half-counted shelf behind
        // every dropped connection.
        Route::post('count', [StockController::class, 'count']);
    });
});
