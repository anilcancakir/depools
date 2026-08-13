<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Services\BarcodeResolver;
use App\Support\ProductCandidate;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

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
     * Resolves a scan through the cascade, or 404 when nothing anywhere carries the code.
     *
     * **404 is the answer that starts stage 6**, so it has to mean exactly one thing: no source knows
     * this code. It is what tells the client to offer a photo or a typed entry, and reporting a
     * transport failure the same way would send a user to create a product they already own.
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

        $candidate = $this->resolver->resolve($data['code'], $data['symbology'] ?? null);

        abort_if($candidate === null, 404);

        /** @var ProductCandidate $candidate */
        return response()->json(['data' => $candidate->toArray()]);
    }
}
