<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * A product plus the derived numbers the list screen needs.
 *
 * `quantity` and `earliest_expires_at` come from `product_stock` rather than being computed here,
 * which is the whole reason that table exists: a list of fifty products would otherwise aggregate
 * the ledger fifty times per request. They are `whenLoaded`-gated so a caller that did not ask for
 * stock does not silently pay for it.
 */
final class ProductResource extends JsonResource
{
    /** @return array<string, mixed> */
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'name' => $this->name,
            'brand' => $this->brand,
            'sku' => $this->sku,
            'base_unit' => $this->base_unit,
            'tracks_expiry' => (bool) $this->tracks_expiry,
            'content_amount' => $this->content_amount,
            'content_unit' => $this->content_unit,
            'par_level' => $this->par_level,
            'tracking_mode' => $this->tracking_mode,
            // Formatted to the column's own precision rather than cast from the summed float.
            // `product_stock.quantity` is `decimal:3`, so a per-location row arrives as `6.000`
            // while the raw sum arrives as `6`, and a client rendering both would show one
            // quantity two ways on the same screen.
            'quantity' => $this->whenLoaded(
                'stock',
                fn (): string => number_format((float) $this->stock->sum('quantity'), 3, '.', ''),
            ),
            // Names rather than objects, because that is the entire payload: the chip renders a name and
            // the filter sends a name back. Sending `{id, name}` pairs would put a second identifier on
            // the wire for a value that is already unique per tenant by its fold.
            'tags' => $this->whenLoaded('tags', fn (): array => $this->tags->pluck('name')->all()),
            'locations' => LocationStockResource::collection($this->whenLoaded('stock')),
        ];
    }
}
