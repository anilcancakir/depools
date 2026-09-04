<?php

namespace App\Http\Requests;

use App\Support\ValidationBounds;
use Illuminate\Foundation\Http\FormRequest;

/**
 * `POST api/v1/icons/suggest`'s rule set: the icon a place's name suggests, or null.
 *
 * **A bare `true`, not a `Gate` call.** A cross-tenant read here answers 404, not 403 (see
 * `TeamScope`), and `FormRequest::failedAuthorization()` throws `AuthorizationException`, which the
 * handler maps to 403. There are zero `Gate::`/`$this->authorize()` calls in any controller today,
 * so an authorization check belongs nowhere in this class.
 */
final class SuggestIconRequest extends FormRequest
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
            // The same bound `LocationController` puts on a name, so a suggestion cannot be the way
            // to send a paragraph to a model, and a name the form accepts is never one this refuses.
            'name' => ['required', 'string', 'max:'.ValidationBounds::NAME_MAX],
        ];
    }
}
