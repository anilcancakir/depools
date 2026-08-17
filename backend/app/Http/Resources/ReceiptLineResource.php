<?php

namespace App\Http\Resources;

use App\Models\Product;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * One line off a receipt: what the paper said, and what it resolved to.
 *
 * **`raw_unit_code` travels beside `resolved_unit` on purpose** (D97). Null on the resolved side
 * means the map did not recognise the code, and that is a state the review screen SHOWS rather than
 * a default it hides: guessing a unit is the one error that changes what every quantity in the
 * ledger means, so the client needs to know the paper said something the app could not map.
 *
 * **`product_name` is a field of its own and the screen does not work without it.** The row draws
 * the resolved product's name beside the verbatim string, `PNR SUT 1LT` against `Pınar Süt 1L`, and
 * that comparison is the whole reason the review screen exists. An id cannot be rendered, and a
 * client fetching the product per line would issue one request per row.
 */
final class ReceiptLineResource extends JsonResource
{
    /** @return array<string, mixed> */
    public function toArray(Request $request): array
    {
        return [
            'line_number' => $this->line_number,
            'raw_name' => $this->raw_name,
            'quantity' => $this->quantity,
            'resolved_unit' => $this->resolved_unit,
            'raw_unit_code' => $this->raw_unit_code,
            'unit_price' => $this->unit_price,
            'line_total' => $this->line_total,
            'resolution' => $this->resolution,
            'resolved_by' => $this->resolved_by,
            'product_id' => $this->product_id,
            // Null where the line resolved to nothing, which in THIS slice is every line:
            // `whenLoaded` answers null for a loaded relation that is itself null, so the closure
            // only ever runs for a real product. The relation has to be loaded for the key to appear
            // at all, which is what keeps a list from lazy-loading one product per row.
            'product_name' => $this->whenLoaded('product', fn (Product $product): string => $product->name),
            'confidence' => $this->confidence,
            'confirmed_at' => $this->confirmed_at?->toIso8601String(),
        ];
    }
}
