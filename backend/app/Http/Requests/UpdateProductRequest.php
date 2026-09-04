<?php

namespace App\Http\Requests;

use App\Support\ValidationBounds;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * `PUT api/v1/products/{product}`'s rule set, for the fields a person edits by hand.
 *
 * **A PARTIAL update, which is what `sometimes` on every rule buys.** The product screen edits one
 * row at a time through `FieldEditorSheet`, so a request carries the single field that changed.
 * Without `sometimes` an absent key is an empty one, and saving a brand would blank the SKU beside
 * it: the user fixes one value and watches a second disappear.
 *
 * The difference between "leave it alone" and "empty it" therefore rides on the key being present,
 * which is the same distinction `UpdateProductTargetRequest` makes with `present` and the opposite
 * default. That one has a single field and always sends it; this one has four and sends one.
 *
 * **Deliberately narrower than `StoreProductRequest`.** The unit, the expiry settings and the
 * content breakdown are not here: a base unit is what every movement in the ledger is denominated
 * in, so changing it after the fact would reinterpret history rather than correct a typo, and the
 * screen offers no control for it. A field arriving anyway is ignored rather than refused, because
 * `validate()` returns only what it names.
 *
 * **A bare `true`, not a `Gate` call.** A cross-tenant write here answers 404, not 403: `TeamScope`
 * applies inside the query so the row is not found at all, and `FormRequest::failedAuthorization()`
 * throws `AuthorizationException`, which the handler maps to 403. A 403 would let a tenant
 * enumerate another tenant's identifiers one request at a time.
 */
final class UpdateProductRequest extends FormRequest
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
            // `sometimes` plus `required`, which reads oddly and is exactly right: the key may be
            // absent, and if it is present it may not be blank. A product with no name renders as
            // nothing in every list, every search result and every movement row.
            'name' => ['sometimes', 'required', 'string', 'max:'.ValidationBounds::NAME_MAX],
            'brand' => ['sometimes', 'nullable', 'string', 'max:'.ValidationBounds::BRAND_MAX],
            'description' => ['sometimes', 'nullable', 'string', 'max:2000'],
            // **`ignore` is the half a copied create rule gets wrong.** Unique within the tenant, as
            // on create, and excluding this product's own row: editing the NAME sends the unchanged
            // SKU along with it, which would otherwise collide with itself and refuse a save that
            // changes nothing about the SKU at all.
            'sku' => [
                'sometimes',
                'nullable',
                'string',
                'max:'.ValidationBounds::SKU_MAX,
                Rule::unique('products', 'sku')
                    ->ignore($this->route('product'))
                    ->where('team_id', $this->user()->current_team_id)
                    ->whereNull('deleted_at'),
            ],
        ];
    }
}
