<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;

/**
 * `POST api/v1/print-batches/{printBatch}/settle`'s rule set: records that some or all of a batch
 * came off a printer.
 *
 * **A bare `true`, not a `Gate` call.** A cross-tenant read here answers 404, not 403 (see
 * `TeamScope`), and `FormRequest::failedAuthorization()` throws `AuthorizationException`, which the
 * handler maps to 403. There are zero `Gate::`/`$this->authorize()` calls in any controller today,
 * so an authorization check belongs nowhere in this class.
 */
final class SettlePrintBatchRequest extends FormRequest
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
            // Capped to match `items` on the store/add-lines rule sets: the members were validated and
            // the size was not, so an arbitrarily large array reached `array_diff` and a `whereIn`.
            'positions' => ['sometimes', 'array', 'max:200'],
            'positions.*' => ['integer', 'min:1'],
        ];
    }
}
