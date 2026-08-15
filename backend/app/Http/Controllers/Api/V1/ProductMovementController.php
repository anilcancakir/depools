<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Resources\MovementResource;
use App\Models\Product;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;

/**
 * A product's ledger entries, newest first.
 *
 * **The activity card on the product screen rendered three invented rows before this**, the same
 * three for every product, in Turkish, on an app whose default locale is English. They sat behind
 * `demo-data-start` markers so the hardcoded-copy gate exempted them by design, which is right for a
 * product NAME standing in for a tenant's own and wrong for a movement reason: that is app copy the
 * server names as an enum.
 *
 * ### It reads the ledger rather than a summary
 *
 * Stock is a ledger and the balance is derived from it, so the audit trail IS the movements table.
 * Nothing is computed here beyond ordering: a user reads this when a number looks wrong, and a
 * summary would be one more thing that could disagree with the rows it summarises.
 *
 * ### Tenancy needs no argument here, which is the point of doing it this way
 *
 * The product is resolved through its own scope first, so a product belonging to another tenant is a
 * 404 before any movement is read, and the movements are then reached THROUGH that product. There is
 * no team parameter and no second scope to keep in step.
 */
final class ProductMovementController extends Controller
{
    /**
     * How many entries one page carries.
     *
     * The card shows a handful and offers "see all"; a product counted weekly for a year has a few
     * hundred movements, so an unbounded read would be fine today and a problem for exactly the
     * tenant who has used the product longest.
     */
    private const PER_PAGE = 25;

    public function index(Product $product): AnonymousResourceCollection
    {
        $movements = $product->movements()
            // The actor and the location are what the row's meta line says, so loading them here is
            // the difference between one query and one per row on a screen that shows twenty-five.
            ->with(['actor', 'location'])
            ->latest('created_at')
            // **`id` after `created_at`, because a batch writes many rows in the same second.** A
            // receive of eight lines shares one timestamp to the second, and without a tiebreaker
            // their order is whatever the planner chose, which changes between pages and makes a
            // cursor skip or repeat a row.
            ->latest('id')
            ->paginate(self::PER_PAGE);

        return MovementResource::collection($movements);
    }
}
