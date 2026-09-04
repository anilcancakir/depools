<?php

namespace App\Http\Requests;

use App\Labels\SheetTemplate;
use App\Support\ValidationBounds;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * `PUT api/v1/print-batches/{printBatch}`'s rule set: changes a batch's template or its field
 * selection.
 *
 * **A bare `true`, not a `Gate` call.** A cross-tenant read here answers 404, not 403 (see
 * `TeamScope`), and `FormRequest::failedAuthorization()` throws `AuthorizationException`, which the
 * handler maps to 403. There are zero `Gate::`/`$this->authorize()` calls in any controller today,
 * so an authorization check belongs nowhere in this class.
 */
final class UpdatePrintBatchRequest extends FormRequest
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
            'template' => ['sometimes', 'string', Rule::in(SheetTemplate::keys())],
            'fields' => ['sometimes', 'array', 'min:1'],
            'fields.*' => ['string', Rule::in((array) config('labels.fields'))],
        ];
    }
}
