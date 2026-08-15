<?php

namespace App\Models\Concerns;

use Illuminate\Contracts\Filesystem\Cloud;
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
 *
 * **Used by `GlobalProduct` alone now.** A tenant's own product has a GALLERY rather than one column,
 * so `Product::image_url` reads its primary `product_images` row; the same conversion lives on
 * `ProductImage::url`. The shared catalogue keeps one picture per row on purpose: it is a description
 * of a thing rather than a record of one shelf, and a contributor's second photograph of the same
 * carton adds nothing a lookup needs.
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

        // **Built on the disk the bytes were WRITTEN to, which is not always the default one.** A
        // location's photograph goes to `media.images.disk` while `filesystems.default` is `local`, so
        // the plain `Storage::url` here would answer a url for a disk that does not hold the file.
        // They no longer even coincide by accident: the local disk falls back to `/storage/<path>`
        // while the public disk is served at `APP_URL/media` (D120), so reading the wrong one now
        // produces a url that resolves to the other disk's route.
        //
        // Typed as `Cloud` rather than `Filesystem` because that is the contract declaring `url()`,
        // which the local adapter provides: an annotation of what the object IS, not a suppression.
        /** @var Cloud $disk */
        $disk = Storage::disk($this->imageDisk());

        return URL::to($disk->url($path));
    }

    /**
     * Which disk holds this row's image.
     *
     * The default is the application default, which is right for `global_products`: a catalogue
     * picture is written by `CatalogueContributor` and copied from `filesystems.default`. A model
     * whose uploads go elsewhere overrides this, and `Location` does.
     */
    protected function imageDisk(): ?string
    {
        return null;
    }
}
