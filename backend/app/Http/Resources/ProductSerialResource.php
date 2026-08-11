<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * One individually identified unit: a serial and what is known about it.
 *
 * The counterpart to [StockLotResource], and the differences are the whole of D28 rather than a
 * naming variation. There is no remaining amount, because a unit is present or it is not and half a
 * drill does not exist. The date that matters is a warranty end rather than an expiry. And a unit
 * that has left is marked rather than removed, so the history survives the sale.
 *
 * The client reuses its expiry machinery for the warranty on purpose: same derived window, same
 * badge, same place in the attention list. A warranty running out and a carton going off are the
 * same shape of problem, and two mechanisms would be two things to keep in sync.
 */
final class ProductSerialResource extends JsonResource
{
    /** @return array<string, mixed> */
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'location_id' => $this->location_id,
            'serial' => $this->serial,
            'warranty_ends_at' => $this->warranty_ends_at?->toDateString(),
            'acquired_at' => $this->acquired_at?->toDateString(),
            // Non-null means the unit is gone: sold, written off or otherwise released. Counted out
            // of every total and kept in the list, which is why this travels rather than the row
            // being filtered server-side.
            'released_at' => $this->released_at?->toDateString(),
        ];
    }
}
