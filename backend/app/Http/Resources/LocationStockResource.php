<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * How much of a product sits at one location, and what binds first there.
 *
 * `earliest_expires_at` is the BINDING date rather than the printed one: an opened lot shortens it,
 * so the client's expiry badge and the server's FEFO order agree without the client knowing the
 * opened-shelf-life rule.
 */
final class LocationStockResource extends JsonResource
{
    /** @return array<string, mixed> */
    public function toArray(Request $request): array
    {
        return [
            'location_id' => $this->location_id,
            'quantity' => $this->quantity,
            'earliest_expires_at' => $this->earliest_expires_at?->toDateString(),
            'lots_count' => $this->lots_count,
        ];
    }
}
