<?php

use App\Http\Controllers\Api\V1\BarcodeController;
use App\Http\Controllers\Api\V1\DashboardController;
use App\Http\Controllers\Api\V1\ExpiringController;
use App\Http\Controllers\Api\V1\IconController;
use App\Http\Controllers\Api\V1\LocationController;
use App\Http\Controllers\Api\V1\ProductController;
use App\Http\Controllers\Api\V1\ProductImageController;
use App\Http\Controllers\Api\V1\ProductMovementController;
use App\Http\Controllers\Api\V1\ReceiptController;
use App\Http\Controllers\Api\V1\RunningLowController;
use App\Http\Controllers\Api\V1\SearchController;
use App\Http\Controllers\Api\V1\ShoppingListController;
use App\Http\Controllers\Api\V1\StockController;
use App\Http\Controllers\Api\V1\TeamSettingsController;
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
| Paths are English and plural, and so are the app's own URLs. This comment used to say the app's
| were Turkish, on the argument that a screen's URL is read by the person using the product: the
| premise is right and the conclusion does not follow, because the primary market is outside Turkey
| (D116) and the default locale is `en`, so that reader cannot read a Turkish path either.
| `.claude/rules/backend.md` records the correction and `test/routes/route_paths_test.dart` enforces
| it.
|
| No route accepts a team identifier in any form. `data-model.md`'s first tenancy rule is that
| `team_id` comes from the auth context only, and the surest way to keep that true is for the
| parameter not to exist.
*/

Route::middleware('auth:sanctum')->prefix('v1')->group(function (): void {
    Route::apiResource('locations', LocationController::class)->only(['index', 'store', 'show']);

    // A location's photograph (D119). PUT rather than POST, because a location holds ONE picture:
    // a second upload replaces the first rather than appending to a gallery, which is what the
    // product route does and why the two verbs differ.
    Route::put('locations/{location}/image', [LocationController::class, 'storeImage']);

    // The vocabulary a client offers in a picker, and the one deliberate way a tenant extends it. No
    // update and no delete: a unit with products counted in it is what every delta in their ledger is
    // denominated in, so the foreign key is `restrictOnDelete` and a rename would reinterpret history.
    // The icon catalogue: one route for the picker's search and for resolving what is on screen.
    // Global rather than team-scoped, which the controller says out loud.
    Route::get('icons', [IconController::class, 'index']);

    // POST for a read, because it spends a model call and one of the tenant's credits. The
    // controller carries the argument.
    Route::post('icons/suggest', [IconController::class, 'suggest']);

    // Team-wide settings, as opposed to the per-user, per-device ones the client keeps locally.
    // No team parameter anywhere: the team is the authenticated one.
    Route::get('team/settings', [TeamSettingsController::class, 'show']);
    Route::put('team/settings', [TeamSettingsController::class, 'update']);

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

    // The audit trail, which the product screen's activity card reads. Nested under the product
    // because that is also its tenancy: the product resolves through its own scope first, so
    // another tenant's is a 404 before a movement is touched.
    Route::get('products/{product}/movements', [ProductMovementController::class, 'index']);

    // **The landing screen, in one request.** Four calls racing each other is how a dashboard gets
    // four loading states and two counters computed either side of midnight; the controller carries
    // the argument.
    Route::get('dashboard', DashboardController::class);

    // **One box, two kinds of answer.** Two calls the client made itself could disagree about a
    // spinner, and the screen's whole value is that one field answers both questions.
    Route::get('search', SearchController::class);

    // **What is running out of time**, which is the middle of the product's three promises and the
    // one nothing answered. Lots and warranties in one list, because the screen treats them alike.
    Route::get('expiring', [ExpiringController::class, 'index']);

    // **What is short**, which is the diagnosis half of D57's pair. Flat and unpaginated like
    // `expiring`: the result is already bounded by the question, and a screen answering "what do I
    // need to deal with" is unusable a page at a time.
    Route::get('running-low', [RunningLowController::class, 'index']);

    // **What to buy**, which is the action half of D57's pair, and the only one of the three
    // forecasting surfaces with state: a tick and a hand-typed line have nowhere else to live. A
    // tick is NOT a stock movement (D47), so nothing under here reaches `StockWriter`.
    Route::get('shopping', [ShoppingListController::class, 'index']);
    Route::post('shopping', [ShoppingListController::class, 'store']);
    Route::put('shopping/{shopping}', [ShoppingListController::class, 'update']);
    Route::delete('shopping/{shopping}', [ShoppingListController::class, 'destroy']);

    // **A photographed receipt**, and in this slice nothing more: the file is stored, a row exists
    // immediately, and a second upload of the same file is answered with the receipt that already
    // holds it. No extraction, no resolution and no stock write, so a receipt here has zero lines
    // and that is its normal state.
    //
    // Declared one verb at a time rather than through `apiResource`, like `expiring` and
    // `running-low` above, so no unimplemented method can be reached: a resource would publish
    // `update` and `destroy` routes that answer 500 rather than 404.
    //
    // There is deliberately no route serving the document. It sits on the private disk, and a
    // streaming action is an authorization surface (tenancy, `document_deleted_at`, `nosniff`) that
    // nothing in this slice would call, so it lands in slice 2 with the tests it needs.
    // **The read, as a POST.** It spends a credit and writes rows, so it is neither safe nor
    // cacheable; `icons/suggest` carries the same argument. Declared before the `{receipt}` routes
    // out of habit rather than necessity: `extract` is a second segment and cannot collide with
    // them.
    Route::post('receipts/{receipt}/extract', [ReceiptController::class, 'extract']);

    Route::get('receipts', [ReceiptController::class, 'index']);
    Route::post('receipts', [ReceiptController::class, 'store']);
    Route::get('receipts/{receipt}', [ReceiptController::class, 'show']);

    // **How much of this to keep on hand**, which is the one number the app asks a person for. Its
    // own route rather than a general product update: one field, named for its question, and a
    // general endpoint would have to accept fields no screen sends yet. The reorder point is
    // deliberately not settable here (D48): the app infers it from the tenant's shopping rhythm and
    // the phrase "lead time" never reaches the interface.
    //
    // Declared before the resource out of habit rather than necessity: `products/by-barcode` HAS to
    // be, because it collides with `GET products/{product}` on the same verb and segment count, and
    // this one cannot collide with anything the resource generates.
    Route::put('products/{product}/target', [ProductController::class, 'updateTarget']);

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
