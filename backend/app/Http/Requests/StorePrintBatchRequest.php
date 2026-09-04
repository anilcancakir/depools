<?php

namespace App\Http\Requests;

use App\Labels\SheetTemplate;
use App\Support\ValidationBounds;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * `POST api/v1/print-batches`'s rule set: opens a batch, optionally with its first lines.
 *
 * **The item rules are not shared with [AddPrintBatchLinesRequest] through a base class.**
 * `PrintBatchController` used to hold them once as a private `itemRules()` and splice it into both
 * `store` and `addLines`. Splitting the controller's validation into per-action classes means the
 * fragment moves with each: `Must NOT create a base class, trait or interface shared across
 * controllers`, and the same restraint applies within one controller's two classes, so the array is
 * duplicated here and in the other rather than reached for through a shared ancestor.
 *
 * **A bare `true`, not a `Gate` call.** A cross-tenant read here answers 404, not 403 (see
 * `TeamScope`), and `FormRequest::failedAuthorization()` throws `AuthorizationException`, which the
 * handler maps to 403. There are zero `Gate::`/`$this->authorize()` calls in any controller today,
 * so an authorization check belongs nowhere in this class.
 */
final class StorePrintBatchRequest extends FormRequest
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
            'name' => ['sometimes', 'nullable', 'string', 'max:'.ValidationBounds::NAME_MAX],
            'template' => ['required', 'string', Rule::in(SheetTemplate::keys())],
            'fields' => ['sometimes', 'array', 'min:1'],
            'fields.*' => ['string', Rule::in((array) config('labels.fields'))],
            'items' => ['sometimes', 'array', 'max:200'],
            'items.*.product_id' => ['sometimes', 'nullable', 'uuid'],
            'items.*.product_serial_id' => ['sometimes', 'nullable', 'uuid'],
            // D45: a serial's copies are not a number anybody may choose, so the CHECK holds it at one
            // and this refuses it before the database has to.
            'items.*.copies' => [
                'sometimes',
                'integer',
                'min:'.ValidationBounds::LABEL_COPIES_MIN,
                'max:'.ValidationBounds::LABEL_COPIES_MAX,
            ],
        ];
    }
}
