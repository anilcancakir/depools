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
        ];
    }
}
