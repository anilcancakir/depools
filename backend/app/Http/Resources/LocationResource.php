<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * A location, in the shape the Flutter client's `LocationRow` already renders.
 *
 * `full_path` is sent alongside `name` because every screen that lists a location shows the walk
 * to it (`Mutfak › Buzdolabı`), and recomputing that on the client would mean shipping the
 * hierarchy rules twice.
 */
final class LocationResource extends JsonResource
{
    /** @return array<string, mixed> */
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'name' => $this->name,
            'full_path' => $this->full_path,
            'parent_id' => $this->parent_location_id,
            'depth' => $this->depth,
            // How the node is shown (D119). All three are nullable and usually null: a location
            // created by a scan or by the assistant carries none of them.
            //
            // `icon` and `colour` travel as the stored KEYS rather than as anything renderable, which
            // is the same shape `base_unit` uses: the client owns the mapping, because a codepoint
            // cannot survive icon tree-shaking and a hex cannot survive the design-token gate.
            'icon' => $this->icon,
            'colour' => $this->colour,
            // A url rather than the path, because a client cannot turn a path into anything.
            'image_url' => $this->image_url,
            // How many product/location pairs sit here, which the client reads as "does this shelf
            // hold anything". Gated on the caller having asked, so `show` does not pay for a count it
            // does not render.
            'stock_count' => $this->whenCounted('stock'),
        ];
    }
}
