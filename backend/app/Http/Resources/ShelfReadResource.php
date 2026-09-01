<?php

namespace App\Http\Resources;

use App\Models\ShelfRead;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * One shelf read on the wire, with its candidates when they have been loaded.
 *
 * @property-read ShelfRead $resource
 */
final class ShelfReadResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->resource->getKey(),
            'confirmed_at' => $this->resource->confirmed_at?->toIso8601String(),
            'created_at' => $this->resource->created_at?->toIso8601String(),
            // Whether the photograph is still there to draw the boxes on. The screen's whole design
            // rests on the picture staying (D60), so a read whose document went to D94's sweep is a
            // different thing to render and has to say so.
            'has_document' => $this->resource->hasDocument(),
            'candidates' => ShelfCandidateResource::collection(
                $this->whenLoaded('candidates', fn () => $this->resource->candidates, []),
            ),
            // **The outcome of the LAST attempt**, for the reason the receipt slice learned the hard
            // way: a screen that could not tell "you are out of credits" from "we could not read it"
            // redrew the same card after a successful request and looked broken. The client branches
            // on `no_credit`, which is the one the user can act on.
            'last_read_outcome' => $this->whenLoaded(
                'extractions',
                fn () => $this->resource->extractions->last()?->outcome,
            ),
        ];
    }
}
