<?php

namespace App\Support;

use Illuminate\Contracts\Filesystem\Cloud;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Storage;

/**
 * The url a client is given for a stored photograph.
 *
 * ### It is signed, and D120 used to say it did not need to be
 *
 * A tenant's photograph is a picture of their home or business, which
 * `docs/depools-system/legal-and-privacy.md:135` calls personal data and requires to sit behind
 * "private buckets, signed short-lived URLs, no public paths". D120 put the media disk on
 * `visibility => 'public'` for a real reason (a Flutter web build fetches image bytes through XHR and
 * needs Laravel to answer with a CORS header) and recorded, correctly, that `ServeFile` therefore
 * stops asking for a signature. What it did not record is that the two statements contradict each
 * other. Measured on a running server before this class existed: `GET /media/product-images/<uuid>.png`
 * with no token, no signature and no session answered **200**, on a picture of a tenant's own kitchen.
 *
 * Signing is the only credential that fits, and that is a constraint rather than a preference:
 * `Image.network` issues a plain GET and cannot carry an Authorization header, so an `auth:sanctum`
 * route would be unreachable by the widget that needs it. The signature travels in the url the API
 * already hands out.
 *
 * ### `temporaryUrl` and NOT `URL::temporarySignedRoute`, which is the trap here
 *
 * Both produce a plausible signed url against the same route and the same expiry, and they produce
 * DIFFERENT signatures. Only one is accepted. `ServeFile` validates with
 * `hasValidRelativeSignature()`, which computes the hash over the path and query WITHOUT the domain,
 * while `temporarySignedRoute` signs the absolute url. Measured against the running server rather
 * than reasoned about: the `temporarySignedRoute` form answered **403** and the `temporaryUrl` form
 * answered **200**, on the same file in the same second. The first version of this class used the
 * wrong one and its docblock asserted both worked.
 *
 * ### The expiry is rounded to the hour ON PURPOSE
 *
 * A fresh signature per response would change the url string on every list refresh, and Flutter's
 * `ImageCache` is keyed by url, so a thirty-row product list would re-fetch thirty thumbnails every
 * time the list reloaded. Rounding the expiry down to the hour makes every signature generated within
 * one clock hour byte-identical, so the cache key holds while the link still dies.
 *
 * Lifetime is therefore between one and two hours: two at the top of an hour, one at :59. Anılcan's
 * call, taken with the cache cost in front of him. `ServeFile` sends `no-store` on every response, so
 * there is no HTTP cache this window extends; the only thing it preserves is the in-memory one.
 */
final class MediaUrl
{
    /**
     * How long a signed media url may live, before the rounding below shortens it.
     */
    private const HOURS = 2;

    /**
     * A signed, absolute url for a path on a served disk.
     *
     * Typed as `Cloud` because that is the contract declaring `temporaryUrl()`, which the local
     * adapter provides once the disk carries `serve => true`: an annotation of what the object is,
     * not a suppression.
     */
    public static function signed(string $disk, string $path): string
    {
        /** @var Cloud $storage */
        $storage = Storage::disk($disk);

        return $storage->temporaryUrl($path, self::expiresAt());
    }

    /**
     * The next expiry boundary, shared by every url minted in this clock hour.
     *
     * The whole point is that this is NOT `now()->addHours(2)`: that value moves every second, and a
     * url that changes every second is a cache miss on every render.
     */
    private static function expiresAt(): Carbon
    {
        return Carbon::now()->startOfHour()->addHours(self::HOURS);
    }
}
