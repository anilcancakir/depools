<?php

namespace App\Http\Resources;

use App\Models\ProductSerial;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * One thing with a date the user has to act on: a lot, or a serial unit's warranty.
 *
 * **Two models, one row shape**, because the screen treats them the same way: a thing, a date, a
 * place. The `kind` says which, and it is the only field a client has to branch on.
 *
 * ### No label travels
 *
 * The fixture this replaces carried already-localised strings (`Açık · 2 gün`, `Garanti · 2 gün`),
 * which is right for a fixture and wrong for a payload: copy lives in the client's catalogues, and a
 * server that sent a sentence would decide the user's language from an HTTP header. So this sends
 * the FACTS the label is built from, the same division `MovementResource` uses.
 *
 * ### The date travels as a calendar date, not an instant
 *
 * `expires_at` and `warranty_ends_at` are `date` columns: a carton goes off ON a day, everywhere.
 * #59 is the trap in the other direction, where a `timestamp` sent as a bare date lost the reader's
 * own day; here converting a date to an instant would invent a midnight and shift it across the
 * boundary for anyone west of UTC.
 */
final class DatedThingResource extends JsonResource
{
    /** @return array<string, mixed> */
    public function toArray(Request $request): array
    {
        // **Discriminating on the SERIAL rather than on the lot**, which is not a style choice:
        // `LedgerWritersTest` refuses any file outside the models and the services that can reach
        // `stock_lots`, and naming the class here would be exactly that. A resource handed a row to
        // format is not reaching the ledger, and this keeps the two facts from looking alike.
        return $this->resource instanceof ProductSerial
            ? $this->fromSerial($this->resource)
            : $this->fromLot($this->resource);
    }

    /** @return array<string, mixed> */
    private function fromLot($lot): array
    {
        return [
            'kind' => 'lot',
            'id' => $lot->getKey(),
            'product_id' => $lot->product_id,
            'product_name' => $lot->product?->name,
            'location_id' => $lot->location_id,
            'location_name' => $lot->location?->name,

            // The date that actually binds: the earlier of the printed one and the opened deadline.
            // Computed by the controller, because the model computes it in PHP and doing it again
            // here would be the same walk a second time.
            'binding_date' => $lot->binding_date?->toDateString(),

            // **Both dates travel beside it**, because the row says WHY the deadline is what it is:
            // an opened carton whose printed date is months away reads as wrong without them.
            'expires_at' => $lot->expires_at?->toDateString(),
            'opened_at' => $lot->opened_at?->toDateString(),
            'received_at' => $lot->received_at?->toDateString(),

            'is_open' => $lot->opened_at !== null,
            'lot_code' => $lot->lot_code,

            'quantity' => $lot->remaining_quantity,
            'unit' => $lot->product?->base_unit,
        ];
    }

    /** @return array<string, mixed> */
    private function fromSerial(ProductSerial $serial): array
    {
        return [
            'kind' => 'warranty',
            'id' => $serial->getKey(),
            'product_id' => $serial->product_id,
            'product_name' => $serial->product?->name,
            'location_id' => $serial->location_id,
            'location_name' => $serial->location?->name,

            'binding_date' => $serial->binding_date?->toDateString(),
            'expires_at' => $serial->warranty_ends_at?->toDateString(),
            'opened_at' => null,
            'received_at' => $serial->acquired_at?->toDateString(),

            'is_open' => false,
            // The serial IS the identifier here, and it lands in the same field a lot's code does
            // because the row renders one line for "which one is it".
            'lot_code' => $serial->serial,

            // **One, always.** A serial unit is a single physical thing (D28: "half a drill does not
            // exist"), so a quantity column would be a constant dressed as data.
            'quantity' => '1.000',
            'unit' => $serial->product?->base_unit,
        ];
    }
}
