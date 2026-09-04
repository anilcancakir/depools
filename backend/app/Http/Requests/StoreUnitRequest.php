<?php

namespace App\Http\Requests;

use App\Rules\UnitExists;
use App\Support\ValidationBounds;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * `POST api/v1/units`'s rule set: registers a unit of this tenant's own.
 *
 * **A bare `true`, not a `Gate` call.** A cross-tenant read here answers 404, not 403 (see
 * `TeamScope`), and `FormRequest::failedAuthorization()` throws `AuthorizationException`, which the
 * handler maps to 403. There are zero `Gate::`/`$this->authorize()` calls in any controller today,
 * so an authorization check belongs nowhere in this class.
 */
final class StoreUnitRequest extends FormRequest
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
            'code' => ['required', 'string', 'max:'.ValidationBounds::UNIT_CODE_MAX],
            'name' => ['required', 'string', 'max:'.ValidationBounds::NAME_MAX],
            // The unit this one is a multiple of, which has to be one this tenant can already see.
            'reference_code' => ['nullable', 'string', 'max:'.ValidationBounds::UNIT_CODE_MAX, new UnitExists],
            // Required WITH a reference and refused without one, because a factor against nothing is a
            // number that cannot be interpreted, and the table's CHECK would refuse the row anyway with
            // a constraint violation rather than a sentence.
            //
            // `Rule::prohibitedIf` rather than a `prohibited_without` string, which does not exist:
            // Laravel ships `prohibited`, `prohibited_if`, `prohibited_unless` and `prohibits`, and the
            // invented one fails as `Method validateProhibitedWithout does not exist` at request time
            // rather than as anything a reader would spot.
            'factor' => [
                'nullable',
                'numeric',
                'gt:0',
                'required_with:reference_code',
                Rule::prohibitedIf(fn (): bool => ! $this->filled('reference_code')),
            ],
        ];
    }
}
