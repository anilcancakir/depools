<?php

namespace App\Models\Concerns;

use Illuminate\Support\Facades\Storage;

/**
 * A stored image path, exposed as the URL a client can actually load.
 *
 * **The two are not the same thing and conflating them was about to become a live bug.**
 * `ProductCandidate` carries one `image_url` field, and the resolver was filling it from
 * `global_products.image_path`, which is a path on our disk, alongside `off_products.image_url`, which
 * is a REMOTE url on purpose: that migration records why, since an Open Food Facts photograph is
 * CC-BY-SA and not redistributed. Nothing broke while the client ignored the field; wiring it is what
 * would have made a path reach an image tag.
 *
 * So a path becomes a url here, at the boundary, and a remote url passes through untouched. The shape
 * is the one `magic-starter-laravel` already uses for a profile photo: a `*_path` column plus a `*_url`
 * accessor over `Storage::url`.
 */
trait HasStoredImage
{
    /** The url for this row's stored image, or null when it has none. */
    public function getImageUrlAttribute(): ?string
    {
        $path = $this->image_path;

        if (! is_string($path) || trim($path) === '') {
            return null;
        }

        return Storage::disk(config('filesystems.default'))->url($path);
    }
}
