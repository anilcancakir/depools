<?php

namespace App\Http\Requests;

use App\Support\ValidationBounds;
use Illuminate\Foundation\Http\FormRequest;

/**
 * `GET api/v1/search`'s rule set: one box, two kinds of answer.
 *
 * **A bare `true`, not a `Gate` call.** A cross-tenant read here answers 404, not 403 (see
 * `TeamScope`), and `FormRequest::failedAuthorization()` throws `AuthorizationException`, which the
 * handler maps to 403. There are zero `Gate::`/`$this->authorize()` calls in any controller today,
 * so an authorization check belongs nowhere in this class.
 */
final class SearchRequest extends FormRequest
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
            // The same bound the product list puts on its own query, so a string one screen accepts
            // is never refused by the other.
            'q' => ['required', 'string', 'max:'.ValidationBounds::SEARCH_QUERY_MAX],
        ];
    }
}
