<?php

namespace App\Http\Requests;

use App\Support\ValidationBounds;
use Illuminate\Foundation\Http\FormRequest;

/**
 * `PUT api/v1/print-batches/{printBatch}/lines/{position}`'s rule set: changes how many copies one
 * line prints.
 *
 * **A bare `true`, not a `Gate` call.** A cross-tenant read here answers 404, not 403 (see
 * `TeamScope`), and `FormRequest::failedAuthorization()` throws `AuthorizationException`, which the
 * handler maps to 403. There are zero `Gate::`/`$this->authorize()` calls in any controller today,
 * so an authorization check belongs nowhere in this class.
 */
final class UpdatePrintBatchLineRequest extends FormRequest
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
            'copies' => [
                'required',
                'integer',
                'min:'.ValidationBounds::LABEL_COPIES_MIN,
                'max:'.ValidationBounds::LABEL_COPIES_MAX,
            ],
        ];
    }
}
