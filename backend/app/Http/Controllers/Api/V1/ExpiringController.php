<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Resources\DatedThingResource;
use App\Models\ProductSerial;
use App\Services\StockLedger;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Support\Carbon;
use Illuminate\Support\Collection;

/**
 * What is running out of time: the middle of the product's three promises.
 *
 * The core loop is stock in, what is expiring, what to buy, and until now nothing answered the
 * middle one. The screen was drawn against `expiring_fixtures.dart`, which carries the design; this
 * answers the same shape from the ledger.
 *
 * ### One row per LOT, never per product
 *
 * A carton expiring on Tuesday and one expiring next month are two different decisions, and a row
 * per product would tell a user something needs using without telling them which one to reach for.
 * A product with no lot breakdown still contributes one row, because inbound stock always creates a
 * lot: there is no second shape to handle.
 *
 * ### The horizon is ABSOLUTE, and that is D55 rather than an oversight
 *
 * The obvious design is each product's own D24 window, on the argument that one N cannot serve a
 * five-day milk and a one-year flour. The fixture measured it and got ZERO rows: D24's window for a
 * five-day product is one day, so a carton with two days left was excluded from the one screen built
 * to find it.
 *
 * The two do different jobs. D24's per-product window decides what earns a badge UNPROMPTED, on a
 * screen the user did not open to ask about dates. This endpoint IS the question "what is coming
 * up", so its scope is a horizon the caller sets, and the urgency inside it is the client's badge.
 *
 * ### Warranties are in the list, not filtered out
 *
 * A warranty ending in two days sits beside a cheese that went off yesterday. Depools is not a
 * pantry app, and a list that carried only food would be one more place that assumption got baked
 * in. They travel as the same row shape with a different `kind`, because the screen treats them the
 * same way: a thing, a date, a place.
 *
 * ### Sorted and filtered in PHP, deliberately
 *
 * A lot's real deadline is `StockLot::bindingDate()`, the earlier of the printed date and the
 * opened-shelf-life deadline, and it is computed rather than stored (D84 keeps derivation out of the
 * database). So SQL narrows to a candidate set it can express, and PHP decides the rest. The
 * candidate set is bounded by the horizon on one side and by "opened" on the other, both of which
 * are small for any real tenant.
 */
final class ExpiringController extends Controller
{
    /**
     * How far ahead the screen looks when the caller says nothing.
     *
     * Seven, matching `defaultHorizonDays` on the client. Stated in both places rather than sent,
     * because a default the server owns would make the screen's own copy ("within 7 days") a lie the
     * moment the two disagreed, and the client already offers other horizons.
     */
    private const DEFAULT_HORIZON = 7;

    /**
     * The furthest a caller may look.
     *
     * A year, because the screen's longest offered horizon is far shorter and an unbounded value is
     * a way to ask for every lot the tenant has ever held in one request.
     */
    private const MAX_HORIZON = 365;

    public function __construct(private readonly StockLedger $ledger) {}

    public function index(Request $request): AnonymousResourceCollection
    {
        $data = $request->validate([
            'horizon' => ['nullable', 'integer', 'min:0', 'max:'.self::MAX_HORIZON],
        ]);

        $horizon = (int) ($data['horizon'] ?? self::DEFAULT_HORIZON);
        $until = Carbon::today()->addDays($horizon);

        return DatedThingResource::collection(
            $this->ledger->lotsBindingBy($until)
                ->concat($this->warranties($until))
                // **Ordered by the date, not by the table it came from.** The screen is a queue of
                // things to deal with, and a cheese that went off yesterday belongs above a warranty
                // ending next week whichever query found it.
                ->sortBy(static fn (object $row): string => $row->binding_date->toDateString())
                ->values(),
        );
    }

    /**
     * Serial units whose warranty ends inside the horizon.
     *
     * @return Collection<int, ProductSerial>
     */
    private function warranties(Carbon $until): Collection
    {
        return ProductSerial::query()
            // A released unit is kept as history (the model says why) and is not the tenant's problem
            // any more, so its warranty is not either.
            ->whereNull('released_at')
            ->whereNotNull('warranty_ends_at')
            ->where('warranty_ends_at', '<=', $until)
            ->with(['product', 'location'])
            ->get()
            ->each(function (ProductSerial $serial): void {
                $serial->binding_date = $serial->warranty_ends_at;
            });
    }
}
