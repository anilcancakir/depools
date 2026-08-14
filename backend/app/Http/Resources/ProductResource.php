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
            'description' => $this->description,
            'sku' => $this->sku,
            'base_unit' => $this->base_unit,
            // **The column existed and nothing exposed it**, so no list row and no detail screen could
            // show a picture even for a product that had one. A url rather than the path, because a
            // client cannot turn a path into anything.
            'image_url' => $this->image_url,
            'tracks_expiry' => (bool) $this->tracks_expiry,
            'content_amount' => $this->content_amount,
            'content_unit' => $this->content_unit,
            'par_level' => $this->par_level,
            'reorder_point' => $this->reorder_point,
            'tracking_mode' => $this->tracking_mode,
            'product_category_id' => $this->product_category_id,
            // The warning window is derived from the shelf life PER PRODUCT rather than being one
            // global number, so the client needs the shelf life itself: seven days always warns about
            // a five-day carton and never warns about a tin. `opened_shelf_life_days` travels with it
            // because an opened unit runs on that clock instead (D27).
            'default_shelf_life_days' => $this->default_shelf_life_days,
            'opened_shelf_life_days' => $this->opened_shelf_life_days,
            // The window itself, and not only the shelf life it comes from. The client had its own
            // copy of `clamp(round(life * 0.2), 1, 60)` in Dart, and the server needs the same number
            // to answer the "expiring soon" filter, so the formula existed twice in two languages: the
            // badge and the filter would have disagreed about one carton the day either side was
            // tuned. `Product::expiryThresholdDays` is now the only implementation and this is how it
            // reaches the screen.
            'expiry_threshold_days' => $this->resource->expiryThresholdDays(),
            // How much history exists, which is the only thing that decides what may be CLAIMED about
            // this product: `forecasting.md` gates a rate on roughly ten movements, and below that the
            // client shows context or nothing rather than a number. Gated on the caller having asked,
            // so a detail request does not pay for a count it will not render.
            'movements_count' => $this->whenCounted('movements'),
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
            // Gated, and the gate is the point rather than a micro-optimisation. A list row renders
            // one number and one badge, so it reads the projection; the detail screen exists to show
            // the batches BEHIND that number. Sending lots to a fifty-row list would be the whole
            // ledger on the wire for a screen that cannot draw it.
            'lots' => StockLotResource::collection($this->whenLoaded('lots')),
            'serials' => ProductSerialResource::collection($this->whenLoaded('serials')),
        ];
    }
}
