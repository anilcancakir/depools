<?php

namespace App\Http\Requests;

use App\Support\ValidationBounds;
use Illuminate\Foundation\Http\FormRequest;

/**
 * `POST api/v1/barcodes/resolve`'s rule set: what a scanned barcode is.
 *
 * **A bare `true`, not a `Gate` call.** A cross-tenant read here answers 404, not 403 (see
 * `TeamScope`), and `FormRequest::failedAuthorization()` throws `AuthorizationException`, which the
 * handler maps to 403. There are zero `Gate::`/`$this->authorize()` calls in any controller today,
 * so an authorization check belongs nowhere in this class.
 */
final class ResolveBarcodeRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    /**
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        return [
            // 128 because `barcodes.code` is `string(128)`: anything longer could never have been
            // stored and so can never resolve, and a 404 there would mean "unknown product" when the
            // truth is "this API cannot hold that value".
            'code' => ['required', 'string', 'max:'.ValidationBounds::BARCODE_CODE_MAX],
            // Part of the identity for a non-GTIN label rather than a hint, since the same characters
            // as Code128 and as a QR are two different labels. Absent for a GTIN, which needs none.
            'symbology' => ['nullable', 'string', 'max:'.ValidationBounds::SYMBOLOGY_MAX],
        ];
    }
}
