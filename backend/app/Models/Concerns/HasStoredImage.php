<?php

namespace App\Models\Concerns;

use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Facades\URL;

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
    /**
     * The url for this row's stored image, or null when it has none.
     *
     * **`URL::to` around `Storage::url`, because the local disk answers a root-relative path.** With no
     * `url` key on the disk, `FilesystemAdapter::getLocalUrl` returns `/storage/<path>` rather than
     * throwing, and `local` is this app's default (`FILESYSTEM_DISK=local`, and the `local` disk in
     * `config/filesystems.php` carries `serve` but no `url`). Measured, not read: tinker on this
     * configuration answers `/storage/products/x.jpg`.
     *
     * That string is unusable from either client. A Flutter mobile build throws `No host specified in
     * URI`, and a web build resolves it against the app's OWN origin, which is a different port from
     * the API, so it 404s. `URL::to` prepends `APP_URL` and passes an already-absolute url straight
     * through (`UrlGenerator::to` returns early on `isValidUrl`), so `public` and `s3` are unaffected.
     */
    public function getImageUrlAttribute(): ?string
    {
        $path = $this->image_path;

        if (! is_string($path) || trim($path) === '') {
            return null;
        }

        // `Storage::url` rather than `Storage::disk(config('filesystems.default'))->url`: the facade
        // already proxies to the default disk, and `disk()` is typed as the `Filesystem` contract,
        // which does not declare `url()` (it lives on `Cloud`). The longer form made the editor report
        // an undefined method on every read.
        return URL::to(Storage::url($path));
    }
}
