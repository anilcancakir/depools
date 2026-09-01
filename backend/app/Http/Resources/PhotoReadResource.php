<?php

namespace App\Http\Resources;

use App\Support\PhotoRead;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * What a photograph read into, on the wire.
 *
 * @property-read PhotoRead $resource
 */
final class PhotoReadResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            // **`found` rather than letting the client infer it from a null name.** The screen has
            // three states to draw (a card, nothing recognised, no credit) and inferring the middle
            // one from an absence is how the receipt screen ended up unable to tell it from the
            // third.
            'found' => $this->resource->found(),
            'cached' => $this->resource->cached,
            // An `AiOutcome` value, or null when the catalogue answered. The client branches on
            // `no_credit`, which is the one the user can do something about.
            'outcome' => $this->resource->outcome,
            // The key a save sends back so the card can be recorded against the photograph it came
            // from. Always present, because a photograph that read into nothing still has a hash and
            // the client still has to send it if the user types the card by hand.
            'image_phash' => $this->resource->imagePhash,
            'name' => $this->resource->name,
            'brand' => $this->resource->brand,
            'description' => $this->resource->description,
            'category_id' => $this->resource->categoryId,
            // The label as well as the id, so the draft can show the category without a second
            // request for a name it is about to render once.
            'category_label' => $this->resource->categoryLabel,
            'unit' => $this->resource->unit,
        ];
    }
}
