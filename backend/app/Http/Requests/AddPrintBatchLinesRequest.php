<?php

namespace App\Http\Requests;

use App\Support\ValidationBounds;
use Illuminate\Foundation\Http\FormRequest;

/**
 * `POST api/v1/print-batches/{printBatch}/lines`'s rule set: adds lines to a batch, which is the
 * "over time" half of what a batch is for.
 *
 * **The item rules are duplicated from [StorePrintBatchRequest] rather than shared.** See that
 * class's docblock for why: the controller's own `itemRules()` helper cannot follow the validation
 * into two separate classes without becoming a base class the plan-wide guardrails forbid.
 *
 * A bare `true`, not a `Gate` call: a cross-tenant read here answers 404, not 403 (see `TeamScope`),
 * and `FormRequest::failedAuthorization()` throws `AuthorizationException`, which the handler maps
 * to 403. There are zero `Gate::`/`$this->authorize()` calls in any controller today, so an
 * authorization check belongs nowhere in this class.
 */
final class AddPrintBatchLinesRequest extends FormRequest
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
            'items' => ['required', 'array', 'min:1', 'max:200'],
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
