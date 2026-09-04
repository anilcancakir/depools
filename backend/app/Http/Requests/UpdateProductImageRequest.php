<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;

/**
 * `PATCH api/v1/products/{product}/images/{image}`'s rule set: makes a picture the primary one, or
 * moves it in the order.
 *
 * **Validated before `ProductImageController::update` looks the product and picture up**, which
 * reorders one thing relative to the inline `$request->validate()` this replaces: the controller
 * used to resolve both `findOrFail` calls FIRST and validate the payload second, so a foreign id
 * carrying an invalid payload answered 404. A `FormRequest` validates as it is resolved, which is
 * before the method body runs, so that combination now answers 422 instead. Accepted rather than
 * fixed, the same direction `LocationController::storeImage` took in an earlier step: 422 is now the
 * answer for every id rather than only for the tenant's own. The suite's own tenancy test
 * (`test_another_tenants_product_is_not_found_rather_than_forbidden`) sends a valid payload against
 * a foreign id, so it is unaffected.
 *
 * **A bare `true`, not a `Gate` call.** A cross-tenant read here answers 404, not 403 (see
 * `TeamScope`), and `FormRequest::failedAuthorization()` throws `AuthorizationException`, which the
 * handler maps to 403. There are zero `Gate::`/`$this->authorize()` calls in any controller today,
 * so an authorization check belongs nowhere in this class.
 */
final class UpdateProductImageRequest extends FormRequest
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
            'is_primary' => ['sometimes', 'boolean'],
            // **Bounded by the COLUMN, not by the gallery's size.** `position` is a sort key rather
            // than an index: it is not renumbered on insert, so a picture appended after one that was
            // moved to 7 legitimately takes 8, and a `max:MAX_PER_PRODUCT - 1` here would refuse a
            // value `store` had just written. `unsignedSmallInteger` is what actually constrains it.
            'position' => ['sometimes', 'integer', 'min:0', 'max:65535'],
        ];
    }
}
