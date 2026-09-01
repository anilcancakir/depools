<?php

namespace App\Http\Resources;

use App\Models\ShelfCandidate;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * One region on the wire.
 *
 * The field names are the CLIENT's: `ShelfCandidate` in `lib/app/models/shelf_read.dart` carries
 * `region`, `left`, `top`, `width`, `height`, `productName`, `resolution`, `quantity` and `unit`.
 * Matching them means the screen's own model parses this without a translation layer, and a rename on
 * either side becomes a failing test rather than a blank row.
 *
 * (This used to name `shelf_fixtures.dart` and the field `amount`. The class moved out of the
 * fixtures when the screen was wired, and the field was always `quantity`.)
 *
 * @property-read ShelfCandidate $resource
 */
final class ShelfCandidateResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->resource->getKey(),
            // D60: the number is the only thing tying this row to a box on the photograph, so it
            // travels first and it is never derived from the array's order.
            'region' => $this->resource->region,
            'left' => $this->resource->box_left,
            'top' => $this->resource->box_top,
            'width' => $this->resource->box_width,
            'height' => $this->resource->box_height,
            // Null when the model saw something it could not name, which `ai-enrichment.md` requires
            // be presented rather than invented.
            'product_name' => $this->resource->raw_name,
            'product_id' => $this->resource->product_id,
            'resolution' => $this->resource->resolution,
            // A decimal string, so the number survives the trip the way a receipt line's does.
            'quantity' => $this->resource->quantity,
            'raw_unit_code' => $this->resource->raw_unit_code,
            'unit' => $this->resource->resolved_unit,
            // **Whether a movement already exists for this region, and the client cannot work it out
            // from anything else.** `ShelfCommitter` skips an answered candidate and the commit
            // endpoint has no re-commit refusal, so a second submit writes nothing and answers 200.
            // Without this the screen counted written regions on its accept button and reported them
            // again in its success message. The timestamp travels rather than a boolean because
            // every other date on this API does.
            'confirmed_at' => $this->resource->confirmed_at?->toIso8601String(),
        ];
    }
}
