<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;

/**
 * `PUT api/v1/products/{product}/target`'s rule set.
 *
 * **Validated before `ProductController::updateTarget` looks the product up**, which reorders one
 * thing relative to the inline `$request->validate()` this replaces: the controller used to resolve
 * `$product` through `findOrFail` FIRST and validate second, so a foreign id carrying an invalid
 * payload answered 404. A `FormRequest` validates as it is resolved, which is before the method body
 * runs, so that combination now answers 422 instead. Accepted rather than fixed, the same direction
 * `LocationController::storeImage` took in an earlier step: 422 is now the answer for every id
 * rather than only for the tenant's own, which is one less way to tell an id apart from the outside.
 *
 * **`par_level` is `present`, so an EMPTY body is the cheapest probe of that shift**, and this is the
 * one of the five reordered endpoints where it costs a caller nothing to reach. Both cases are now
 * pinned in `ProductTargetTest`: a valid payload against a foreign id is still 404, an empty one is
 * 422. Before this class neither was.
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
