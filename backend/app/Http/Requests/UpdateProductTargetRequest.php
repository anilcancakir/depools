<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;

/**
 * `PUT api/v1/products/{product}/target`'s rule set.
 *
 * **A bare `true`, not a `Gate` call.** A cross-tenant read here answers 404, not 403 (see
 * `TeamScope`), and `FormRequest::failedAuthorization()` throws `AuthorizationException`, which the
 * handler maps to 403. There are zero `Gate::`/`$this->authorize()` calls in any controller today,
 * so an authorization check belongs nowhere in this class.
 */
final class UpdateProductTargetRequest extends FormRequest
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
            // `present` rather than `required`, so a null is a value and not an omission. Laravel's
            // global `ConvertEmptyStringsToNull` already turns an empty field into null before this
            // runs, which is exactly the clear the user meant.
            'par_level' => ['present', 'nullable', 'numeric', 'gt:0', 'max:999999'],
        ];
    }
}
