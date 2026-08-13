<?php

namespace App\Services;

use App\Models\OffProduct;
use App\Support\Gtin;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use Throwable;

/**
 * Open Food Facts, as a live top-up behind the bulk import.
 *
 * ### Why both, rather than one
 *
 * The bulk export is the base: `barcode-and-catalog.md` requires stages 1 to 3 to work OFFLINE, and a
 * live query cannot. It is also what OFF asks for, in their own words: "1 API call = 1 real scan by a
 * user", with the export named as the way to obtain the database rather than the API.
 *
 * The live call exists for the gap the export cannot close: a product added to OFF after the dump was
 * taken. One request, on a miss the user is standing in front of, which is exactly the "1 real scan"
 * shape rather than a crawl.
 *
 * ### Failing is missing, and that is deliberate
 *
 * A network fault, a timeout or a rate-limit answer all return null, which the cascade reads as "OFF
 * does not have it" and passes to the next stage. The alternative is an error surfaced to a user who
 * is holding a carton and cannot act on it. What it costs is that a transient failure looks like a
 * miss for that one scan; the bulk import is what keeps that rare, and the row is fetched again next
 * time rather than being cached as absent.
 *
 * OFF's read limit is 15 requests per minute per IP, so a burst of scans against products the export
 * does not know can reach it. That is another reason a failure is a miss rather than an error.
 */
final class OpenFoodFacts
{
    /**
     * Short, because a user is waiting with a product in their hand.
     *
     * Three seconds is roughly the point where a scan stops feeling like a lookup and starts feeling
     * broken, and the next stage costs nothing.
     */
    private const TIMEOUT_SECONDS = 3;

    /**
     * OFF requires a custom User-Agent identifying the app and a contact, and rejects generic ones.
     *
     * Named here rather than in config because it is a term of use rather than a setting: an operator
     * who changed it to something anonymous would be violating the API's conditions without knowing.
     */
    private const USER_AGENT = 'Depools/1.0 (https://depools.ai; hello@depools.ai)';

    /**
     * Fetches one product from OFF and stores it, or null when OFF does not answer with one.
     *
     * Stored on the way through, so the second scan of the same product is local. That is the whole
     * point of the top-up: it turns one user's miss into everybody's hit.
     */
    public function fetch(string $gtin): ?OffProduct
    {
        if (! config('services.openfoodfacts.live', true)) {
            return null;
        }

        try {
            $response = Http::withUserAgent(self::USER_AGENT)
                ->timeout(self::TIMEOUT_SECONDS)
                ->get(sprintf(
                    'https://world.openfoodfacts.org/api/v2/product/%s',
                    urlencode($this->apiCode($gtin)),
                ));

            if (! $response->successful()) {
                return null;
            }

            /** @var array<string, mixed> $body */
            $body = $response->json();

            // OFF answers 200 with `status: 0` for a product it does not have, so the status code
            // alone is not the test.
            if (($body['status'] ?? 0) !== 1 || ! is_array($body['product'] ?? null)) {
                return null;
            }

            return $this->store($gtin, $body['product']);
        } catch (Throwable $e) {
            // Logged rather than swallowed, because a persistent failure here is a real operational
            // fact (a blocked IP, a changed contract) that would otherwise present only as OFF
            // "having nothing", which is indistinguishable from an honest miss.
            Log::warning('Open Food Facts lookup failed', ['gtin' => $gtin, 'error' => $e->getMessage()]);

            return null;
        }
    }

    /**
     * The code OFF itself keys on, which is not the one we store.
     *
     * We hold GTIN-14 because GS1 says so; OFF's own normalisation pads to 8 or 13 and does not
     * address 14, so asking it for `08690504010012` misses a product it has under `8690504010012`.
     * Stripping our left padding is the translation between the two conventions.
     */
    private function apiCode(string $gtin): string
    {
        $trimmed = ltrim($gtin, '0');

        return $trimmed === '' ? '0' : $trimmed;
    }

    /**
     * @param  array<string, mixed>  $product
     */
    private function store(string $gtin, array $product): ?OffProduct
    {
        $name = $this->text($product, ['product_name', 'product_name_en', 'generic_name']);

        // A row with no name cannot be presented as a candidate, and storing it would make the next
        // scan skip the live call and find nothing useful. Better to miss and try again.
        if ($name === null) {
            return null;
        }

        return OffProduct::updateOrCreate(
            ['gtin' => (string) Gtin::fromScan($gtin)],
            [
                'name' => $name,
                'brand' => $this->text($product, ['brands']),
                'locale' => $this->locale($product),
                'off_category' => $this->text($product, ['categories']),
                'image_url' => $this->text($product, ['image_front_url', 'image_url']),
                'source_ref' => 'off:api:'.$gtin,
                'imported_at' => now(),
            ],
        );
    }

    /**
     * @param  array<string, mixed>  $product
     * @param  list<string>  $keys
     */
    private function text(array $product, array $keys): ?string
    {
        foreach ($keys as $key) {
            $value = trim((string) ($product[$key] ?? ''));

            if ($value !== '') {
                return mb_substr($value, 0, 255);
            }
        }

        return null;
    }

    /**
     * @param  array<string, mixed>  $product
     */
    private function locale(array $product): string
    {
        $lang = trim((string) ($product['lang'] ?? ''));

        // Two letters, because the column is `string(5)` and OFF's `lang` is an ISO-639-1 code. A
        // longer or empty value falls back to English rather than being stored malformed: the locale
        // decides which users see this row without translation, so a wrong one is worse than a
        // default one.
        return preg_match('/^[a-z]{2}$/', $lang) === 1 ? $lang : 'en';
    }
}
