<?php

namespace App\Http\Requests;

use App\Support\ValidationBounds;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * `POST api/v1/shopping`'s rule set: adds a line by hand.
 *
 * A product id OR a bare name, because both are real: adding "two more of the milk we track" and
 * adding "washing-up liquid" are the same gesture to the user and different rows underneath.
 *
 * **Not merged with [UpdateShoppingListItemRequest] by `$this->method()` branching.** Measured: `store`
 * takes `product_id`, `name` (required), `quantity` (required) and `unit`; `update` takes only
 * `is_checked` and `quantity`, both `sometimes`. That is not one rule set wearing two hats, so two
 * classes is cheaper than a wrong merge.
 *
 * **A bare `true`, not a `Gate` call.** A cross-tenant read here answers 404, not 403 (see
 * `TeamScope`), and `FormRequest::failedAuthorization()` throws `AuthorizationException`, which the
 * handler maps to 403. There are zero `Gate::`/`$this->authorize()` calls in any controller today,
 * so an authorization check belongs nowhere in this class.
 */
final class StoreShoppingListItemRequest extends FormRequest
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
        $teamId = (string) $this->user()->current_team_id;

        return [
            // Scoped to the tenant IN THE RULE, not only by the scope on the model: `Rule::exists`
            // runs its own query with no global scope, so without the `where` a user could attach a
            // line to another tenant's product.
            'product_id' => [
                'nullable',
                'uuid',
                Rule::exists('products', 'id')->where('team_id', $teamId)->whereNull('deleted_at'),
            ],
            // Always required, product or not (D100). The line has to render after the product is
            // deleted, and the user's own wording is worth keeping over the catalogue's.
            'name' => ['required', 'string', 'max:'.ValidationBounds::NAME_MAX],
            'quantity' => ['required', 'numeric', 'gt:0', 'max:999999'],
            'unit' => ['nullable', 'string', 'max:'.ValidationBounds::UNIT_CODE_MAX],
        ];
    }
}
