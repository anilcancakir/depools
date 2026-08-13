<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Services\BarcodeResolver;
use App\Support\Gtin;
use App\Support\ProductCandidate;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\ValidationException;
use InvalidArgumentException;

/**
 * What a scanned barcode is.
 *
 * Thin by design: the cascade's order, its stages and its licence rules live in [BarcodeResolver],
 * because they are decisions about data rather than about HTTP, and stages 4 and 5 are still open.
 * Adding one must change a service and not a controller.
 */
final class BarcodeController extends Controller
{
    public function __construct(private readonly BarcodeResolver $resolver) {}

    /**
     * Whether a raw read could be a GTIN at all.
     *
     * Digits and separators only: `Gtin::fromScan` strips spaces and hyphens because a scanner and a
     * spreadsheet both produce them, so refusing a formatted read here would contradict it. A letter
     * anywhere means it is an internal label rather than a GTIN, whatever its digits would spell.
     */
    private function isGtin(string $code): bool
    {
        $digits = preg_replace('/[\s-]/', '', trim($code)) ?? '';

        if ($digits === '' || preg_match('/^\d+$/', $digits) !== 1) {
            return false;
        }

        try {
            Gtin::fromScan($digits);

            return true;
        } catch (InvalidArgumentException) {
            return false;
        }
    }

    /**
     * Resolves a scan through the cascade, or 404 when nothing anywhere carries the code.
     *
     * **404 is the answer that starts stage 6**, so it has to mean exactly one thing: no source knows
     * this code. It is what tells the client to offer a photo or a typed entry, and reporting a
     * transport failure the same way would send a user to create a product they already own. A code
     * that cannot be identified at all is 422 for the same reason: it is not a product nobody knows.
     */
    public function resolve(Request $request): JsonResponse
    {
        $data = $request->validate([
            // 128 because `barcodes.code` is `string(128)`: anything longer could never have been
            // stored and so can never resolve, and a 404 there would mean "unknown product" when the
            // truth is "this API cannot hold that value".
            'code' => ['required', 'string', 'max:128'],
            // Part of the identity for a non-GTIN label rather than a hint, since the same characters
            // as Code128 and as a QR are two different labels. Absent for a GTIN, which needs none.
            'symbology' => ['nullable', 'string', 'max:16'],
        ]);

        $symbology = $data['symbology'] ?? null;

        // **An unidentifiable code is not an unknown product, and 404 here means the second one.**
        // That status is what starts stage 6: the client offers to create a product carrying this
        // code. A non-GTIN read with no symbology cannot become one, because `Barcode::forCode()`
        // needs the symbology as part of the identity (the same characters as Code128 and as a QR are
        // two different labels), so a 404 would send the user into a flow that cannot finish.
        //
        // 422 rather than 400, so it arrives in the same shape as every other validation failure and
        // the client can read the field name.
        if (! $this->isGtin($data['code']) && ($symbology === null || $symbology === '')) {
            throw ValidationException::withMessages([
                'symbology' => 'A code that is not a GTIN needs its symbology to be identified.',
            ]);
        }

        $candidate = $this->resolver->resolve($data['code'], $symbology);

        abort_if($candidate === null, 404);

        /** @var ProductCandidate $candidate */
        return response()->json(['data' => $candidate->toArray()]);
    }
}
