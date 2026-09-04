<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;

/**
 * `PUT api/v1/shopping/{shopping}`'s rule set: tick, untick, or change how many.
 *
 * **Not merged with [StoreShoppingListItemRequest].** See that class's docblock: the two rule sets
 * share no field, measured rather than assumed.
 *
 * **A bare `true`, not a `Gate` call.** A cross-tenant read here answers 404, not 403 (see
 * `TeamScope`), and `FormRequest::failedAuthorization()` throws `AuthorizationException`, which the
 * handler maps to 403. There are zero `Gate::`/`$this->authorize()` calls in any controller today,
 * so an authorization check belongs nowhere in this class.
 */
final class UpdateShoppingListItemRequest extends FormRequest
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
            'is_checked' => ['sometimes', 'boolean'],
            'quantity' => ['sometimes', 'numeric', 'gt:0', 'max:999999'],
        ];
    }
}
