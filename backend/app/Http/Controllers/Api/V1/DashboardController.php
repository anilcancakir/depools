<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Resources\DatedThingResource;
use App\Http\Resources\MovementResource;
use App\Http\Resources\ProductResource;
use App\Models\Location;
use App\Models\Product;
use App\Services\ProductListQuery;
use App\Services\ShoppingListGenerator;
use App\Services\StockLedger;
use Illuminate\Database\Eloquent\Collection;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;

/**
 * The landing screen, in one request.
 *
 * ### One call rather than four, and the screen's own docblock is the argument
 *
 * `DashboardView` says no figure on it may disagree with the page it links to. Four paginated calls
 * racing each other is how that breaks: four loading states, a subtitle that lands last, and two
 * counters computed either side of midnight. One request also means one reference date, which is the
 * same reasoning `ProductController::index` gives for building its filter once.
 *
 * ### Counts and previews, not pages
 *
 * Every list here is capped and none of them paginate. A dashboard card shows three rows and a "see
 * all" link to the screen that does paginate, so sending more would be bytes nobody renders. The
 * COUNT beside each card is the full figure, taken separately, because "3 of 47" is the sentence the
 * card exists to say.
 *
 * ### What is deliberately absent
 *
 * The shopping card, which needs the forecasting pipeline that `forecasting.md` describes and no
 * code implements yet. The client keeps its fixture there and the gap is named rather than filled
 * with a number nobody computed.
 */
final class DashboardController extends Controller
{
    /**
     * How many rows each card previews.
     *
     * Three, matching what the cards render before their "see all" link. The dates card shows two
     * groups so it gets this for each.
     */
    private const PREVIEW = 3;

    /**
     * The horizon the "approaching" counter uses.
     *
     * Seven, the same default `ExpiringController` and the client's `defaultHorizonDays` carry. The
     * counter's own label says "within 7 days", so a third opinion about the number would put a lie
     * on the card.
     */
    private const HORIZON = 7;

    public function __invoke(StockLedger $ledger, ShoppingListGenerator $shoppingList, Request $request): JsonResponse
    {
        // ONE reference date for the whole response, for the reason `ProductController` records: two
        // reads either side of midnight would count a lot as expired for the card and not for the
        // counter, which reads as a flickering screen rather than as a clock problem.
        $today = Carbon::today();

        $dated = $ledger->lotsBindingBy($today->copy()->addDays(self::HORIZON));

        $expired = $dated->filter(
            static fn (object $lot): bool => $lot->binding_date->lessThan($today),
        )->values();

        $approaching = $dated->filter(
            static fn (object $lot): bool => ! $lot->binding_date->lessThan($today),
        )->values();

        $out = $this->products(['stock_state' => 'out_of_stock'], $today);
        $low = $this->products(['stock_state' => 'below_par'], $today);

        // The same call `ShoppingListController::index` makes, and the same `$today`: two reads
        // either side of midnight would regenerate the list for one of them and not the other.
        $shopping = $shoppingList->forTeam((string) $request->user()->current_team_id, $today);

        return response()->json([
            'data' => [
                // **Whether the tenant has ANY stock, which decides which screen they get.** A fresh
                // tenant sees the setup steps rather than a thinner dashboard: the counters, the four
                // cards and the history all describe stock, so every one of them would render as a
                // zero. Six ways of saying the same nothing.
                'has_stock' => Product::query()->whereHas('stock')->exists(),

                // The subtitle's scope, so a counter reading 6 is legible as six OF something.
                'products' => Product::query()->count(),
                'locations' => Location::query()->count(),

                'counters' => [
                    'expired' => $expired->count(),
                    'approaching' => $approaching->count(),
                    'out_of_stock' => $out['total'],
                    'below_target' => $low['total'],
                    // **What is left to buy, counted from the generator rather than from a query of
                    // its own.** `forTeam` regenerates the list when it is stale, so asking it here
                    // is what makes the counter agree with `/shopping` by construction: a
                    // `ShoppingListItem` count taken directly would report yesterday's list until
                    // the user opened the page, and this screen's whole rule is that no figure on it
                    // disagrees with the page it links to.
                    //
                    // The client had no counter and read its own shopping FIXTURE for both the
                    // card's visibility and its number, so every real tenant saw the demo file.
                    'shopping' => $shopping->whereNull('checked_at')->count(),
                ],

                'expired' => DatedThingResource::collection($expired->take(self::PREVIEW)),
                'approaching' => DatedThingResource::collection($approaching->take(self::PREVIEW)),

                'out_of_stock' => ProductResource::collection($out['rows']),
                'below_target' => ProductResource::collection($low['rows']),

                // The tenant's whole ledger rather than one product's, which is the one thing here
                // no endpoint answered. The query lives in `StockLedger` because `LedgerWritersTest`
                // refuses a controller that can reach `stock_movements`, read or not.
                'activity' => MovementResource::collection($ledger->recentMovements(self::PREVIEW)),
            ],
        ]);
    }

    /**
     * One stock-state slice: the rows a card previews, and the figure beside it.
     *
     * **Two queries on purpose.** The count is the whole set and the rows are the first few, so
     * counting the rows would make every card say "3" however many products are actually short. A
     * fresh builder for each, because a spent one cannot be counted, which is the same shape
     * `ProductController::index` uses for its own total.
     *
     * @param  array<string, mixed>  $criteria
     * @return array{rows: Collection<int, Product>, total: int}
     */
    private function products(array $criteria, Carbon $today): array
    {
        $filter = new ProductListQuery($criteria, $today);

        $rows = $filter->apply(
            Product::query()->with(['stock', 'tags', 'unit', 'primaryImage', 'forecast'])->withCount('movements'),
        )->limit(self::PREVIEW)->get();

        return [
            'rows' => $rows,
            'total' => $filter->apply(Product::query())->count(),
        ];
    }
}
