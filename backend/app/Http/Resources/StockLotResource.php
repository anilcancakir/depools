<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * One lot: a batch with its own date, its own remainder and its own place.
 *
 * The list screen never sees these, and that is the split: a list row shows ONE number and one
 * badge, so it reads the projection, while the detail screen exists to show the batches behind
 * that number and cannot be built from a total.
 *
 * ### Both dates travel, deliberately
 *
 * `expires_at` is what is printed on the carton and `binding_expires_at` is what actually governs
 * it: for an opened lot the after-opening deadline is usually sooner (D27), and it is the one FEFO
 * orders by. Sending only the binding date would be enough to render a badge and would lose the
 * distinction the detail screen exists for, because "opened on Tuesday" and "printed date next
 * month" are two different facts about the same carton and the user is checking which applies.
 *
 * Computed by `StockLot::bindingDate()` rather than here or in the client: it needs the product's
 * `opened_shelf_life_days`, and a second implementation of that comparison is a second answer to
 * "when does this go off".
 */
final class StockLotResource extends JsonResource
{
    /** @return array<string, mixed> */
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'location_id' => $this->location_id,
            'lot_code' => $this->lot_code,
            'expires_at' => $this->expires_at?->toDateString(),
            'binding_expires_at' => $this->bindingDate()?->toDateString(),
            'received_at' => $this->received_at?->toDateString(),
            'opened_at' => $this->opened_at?->toDateString(),
            // Formatted to the column's own scale for the reason `ProductResource` records: the
            // client renders lot remainders next to the product total, and one of them arriving as
            // `1` while the other arrives as `1.000` shows the same quantity two ways on one screen.
            'remaining_quantity' => $this->remaining_quantity,
            'initial_quantity' => $this->initial_quantity,
            // A depleted lot is kept rather than deleted, because it is the evidence behind the
            // consumption history, so the client needs to know to exclude it from totals while
            // still listing it.
            'is_depleted' => (float) $this->remaining_quantity <= 0,
        ];
    }
}
