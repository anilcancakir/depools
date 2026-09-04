<?php

namespace App\Http\Requests;

use App\Models\ProductCategory;
use App\Models\Scopes\TeamScope;
use App\Rules\UnitExists;
use App\Support\ValidationBounds;
use Closure;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * `POST api/v1/products`'s rule set.
 *
 * **A bare `true`, not a `Gate` call.** A cross-tenant read here answers 404, not 403 (see
 * `TeamScope`), and `FormRequest::failedAuthorization()` throws `AuthorizationException`, which the
 * handler maps to 403. There are zero `Gate::`/`$this->authorize()` calls in any controller today,
 * so an authorization check belongs nowhere in this class.
 */
final class StoreProductRequest extends FormRequest
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
            'name' => ['required', 'string', 'max:'.ValidationBounds::NAME_MAX],
            'brand' => ['nullable', 'string', 'max:'.ValidationBounds::BRAND_MAX],
            // **Absent until the photo path sent one, which meant it was silently dropped.**
            // `validate()` returns only what it names, so a description the model read off the
            // packaging reached `store` and went no further: the field is fillable and the column
            // has been there since the first migration.
            'description' => ['nullable', 'string', 'max:2000'],
            // Unique within the tenant only. The reason recorded here used to be that "a partial unique
            // index is not portable to sqlite", which stopped being true when D72 moved the suite onto
            // PostgreSQL: `products_team_sku_unique` now exists and is the real guarantee. This rule
            // stays because it is the only one of the two that can say WHICH product already holds the
            // code, and a 422 naming the conflict beats a 500 from a constraint.
            'sku' => ['nullable', 'string', 'max:64', Rule::unique('products', 'sku')
                ->where('team_id', $this->user()->current_team_id)
                ->whereNull('deleted_at')],
            // A CODE from the shared vocabulary or one this tenant added. `max:16` is the column's
            // shape and [UnitExists] is the vocabulary, which is what replaced this field being free
            // text: an unknown code is a 422 naming the field rather than a new unit nobody meant.
            // **Optional, because the fallback chain exists to answer this.** It was required, which
            // made every caller state a unit even when the team had already said what it counts in.
            // `Product::creating` resolves what the caller named, then the team's `default_unit_id`,
            // then `Unit::fallback()`; a required field here would make the first step the only one.
            // An unknown CODE is still a 422 naming the field: absent and wrong are different.
            //
            // **`nullable` was wrong and would have been a 500.** It let `base_unit: null` through
            // validation, and `Product`'s mutator then ran `Unit::findByCode(null)`, found nothing
            // and threw. A client that spells "no unit" as an explicit null is common enough that
            // the null is stripped below rather than refused: omitted and null mean the same thing
            // here, and neither should be an error.
            'base_unit' => ['sometimes', 'nullable', 'string', 'max:'.ValidationBounds::UNIT_CODE_MAX, new UnitExists],
            'tracks_expiry' => ['boolean'],
            'default_shelf_life_days' => ['nullable', 'integer', 'min:1', 'max:3650'],
            'opened_shelf_life_days' => ['nullable', 'integer', 'min:1', 'max:365'],
            'content_amount' => ['nullable', 'numeric', 'min:0'],
            // **A content unit has to be FINER than the base unit, so it cannot be the same one.**
            // The base unit is what you count and the content is what one of them holds: a carton is
            // `piece` holding `1000 ml`. `base_unit: 'l'` with `content_unit: 'l'` says a litre
            // contains a litre, and the demo seeder shipped six products in exactly that shape. It
            // made the app look wrong where it was not: a 500 g pack read as "2 g" on the count sheet,
            // and the split-quantity field cannot work at all, because half of a base unit is then
            // half of the same unit rather than a count of smaller ones (D26).
            // **The same vocabulary as `base_unit`, or `different` compares two of them.** This field
            // stayed free text while the base unit became a code, which made the rule below trivially
            // satisfiable: `LTR` differs from `l` by spelling rather than by meaning, and the test that
            // pins "a litre cannot contain a litre" went green while a product declared exactly that.
            //
            // Still a string column rather than a second foreign key, which is a deliberate stopping
            // point: nothing computes with a content unit yet, and the pair `(content_amount,
            // content_unit)` is already constrained to travel together.
            'content_unit' => ['nullable', 'string', 'max:'.ValidationBounds::UNIT_CODE_MAX, 'different:base_unit', new UnitExists],
            'par_level' => ['nullable', 'numeric', 'min:0'],

            // **Stage 6 of the cascade arrives here.** A scan that resolved to nothing sends the
            // user to type the card, and the code they scanned has to travel with it or the next
            // scan of the same carton misses again. Absent when a product is added by hand.
            'barcode' => ['nullable', 'string', 'max:'.ValidationBounds::BARCODE_CODE_MAX],
            // Part of a non-GTIN label's identity rather than a hint, same rule as the resolve
            // endpoint: the same characters as Code128 and as a QR are two different labels.
            'symbology' => ['nullable', 'string', 'max:'.ValidationBounds::SYMBOLOGY_MAX],

            // **Default TRUE, which is Anılcan's call and the one the moat depends on.** Turkish
            // barcode coverage in commercial databases is weak, so the catalogue is built out of
            // confirmations, and a contribution model most people never notice contributes nothing.
            // `barcode-and-catalog.md` used to say opt-in per tenant and off by default; that is
            // superseded there, with the argument, rather than quietly contradicted here.
            'contribute' => ['boolean'],

            // **The taxonomy row the photograph resolved to.** Without it the whole resolution
            // cascade in `ProductPhotoReader` produced a value the draft screen drew as a tag and
            // then dropped, and `location_category_affinity` never learned anything from a product
            // created by camera. It also unlocks `Product::creating`'s category-to-unit inference,
            // which cannot fire on a product with no category.
            //
            // Checked through the scope rather than a bare `exists`, because the taxonomy is shared
            // rows plus this tenant's own: `exists` alone would accept another tenant's category.
            'product_category_id' => ['nullable', 'uuid', function (string $attribute, mixed $value, Closure $fail): void {
                $visible = ProductCategory::query()
                    ->visibleTo(TeamScope::currentTeamId())
                    ->whereKey($value)
                    ->exists();

                if (! $visible) {
                    $fail(__('That category does not exist.'));
                }
            }],

            // **The photograph this card was read from, as its perceptual hash.** Present only when
            // the product arrived through `products/recognise`, and it is what makes the NEXT
            // photograph of the same thing free: the hash lands on the contributed catalogue row and
            // the reader looks there before it looks at a model.
            //
            // A hash rather than the picture, so this is not the photo-sharing that
            // `barcode-and-catalog.md` forbids: nothing can be rendered from 64 bits of
            // low-frequency structure. Validated as 32 hex characters because that is the column's
            // shape and because an arbitrary string here would end up in a shared table.
            'image_phash' => ['nullable', 'string', 'size:32', 'regex:/^[0-9a-f]{32}$/'],
        ];
    }
}
