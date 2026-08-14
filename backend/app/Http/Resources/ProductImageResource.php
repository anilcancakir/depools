<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * One picture in a product's gallery.
 *
 * **`url` and not `path`.** Whether a picture is a file on our disk or an address we point at is
 * storage, and a client can load exactly one of those two things; the model answers with whichever
 * applies. Sending the path as well would invite a client to build its own url and get it wrong the
 * day the disk changes.
 *
 * `attribution` travels because a linked photograph is shown under a licence that asks for the credit
 * to be visible. Null for our own upload, which has nobody to credit.
 */
final class ProductImageResource extends JsonResource
{
    /** @return array<string, mixed> */
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'url' => $this->url,
            'attribution' => $this->attribution,
            'source' => $this->source,
            'is_primary' => (bool) $this->is_primary,
            'position' => (int) $this->position,
        ];
    }
}
