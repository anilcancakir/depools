<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * One shopping line: what to buy, and the evidence for why.
 *
 * **No sentence travels** (D98). `forecasting.md`'s third acceptance criterion is that every line
 * states why it is there, and D46 makes the PRECISION of that sentence the uncertainty display. Both
 * are satisfied by sending the reason code and the frozen inputs behind it and letting the client
 * render per locale, which is also the only option: a Turkish string in the database makes the
 * English interface untranslatable.
 *
 * The gate is in the payload rather than in the wording. A `roughly_due` line carries a null
 * `reason_days`, enforced by a CHECK, so no screen can print a figure the history does not support
 * however its copy is written.
 */
final class ShoppingListItemResource extends JsonResource
{
    /** @return array<string, mixed> */
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'product_id' => $this->product_id,
            // The line's own name, always present (D100), so it still renders after the product is
            // deleted and so a user's own wording survives the catalogue's.
            'name' => $this->name,
            'quantity' => $this->quantity,
            'unit' => $this->unit,
            'reason' => $this->reason,
            'reason_days' => $this->reason_days,
            // The middle tier's evidence. A code and never a number, so a bucket cannot be
            // rendered as a measurement however the copy is written.
            'reason_bucket' => $this->reason_bucket,
            'reason_on_hand' => $this->reason_on_hand,
            'reason_lot_is_open' => $this->reason_lot_is_open,
            'reason_target' => $this->reason_target,
            'reason_movement_count' => $this->reason_movement_count,
            // A timestamp rather than a flag, because when it went in the trolley is the thing the
            // receipt reconciles against. The client only needs the boolean, and derives it.
            'checked_at' => $this->checked_at?->toIso8601String(),
        ];
    }
}
