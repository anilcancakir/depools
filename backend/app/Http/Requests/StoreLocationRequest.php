<?php

namespace App\Http\Requests;

use App\Models\Location;
use App\Support\ValidationBounds;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * `POST api/v1/locations`'s rule set.
 *
 * **A bare `true`, not a `Gate` call.** A cross-tenant read here answers 404, not 403 (see
 * `TeamScope`), and `FormRequest::failedAuthorization()` throws `AuthorizationException`, which the
 * handler maps to 403. There are zero `Gate::`/`$this->authorize()` calls in any controller today,
 * so an authorization check belongs nowhere in this class.
 */
final class StoreLocationRequest extends FormRequest
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
            // `exists` runs through the scoped model, so a parent belonging to another tenant fails
            // validation as "does not exist", which is the same answer the read path gives.
            // A uuid, not an integer (D73). The VERSION is the generator's business rather than the
            // API's: validating `uuid:7` here would reject an id this app itself issued if the
            // generator ever changed, and the mixed-version risk D73 names is prevented at
            // generation, not at the boundary.
            'parent_id' => ['nullable', 'uuid'],
            // D119. Both are KEYS into a closed set, not renderable values: the client owns the
            // mapping, because an icon codepoint cannot survive icon tree-shaking and a hex cannot
            // survive the design-token gate. `Rule::in` against the model's own list, so the
            // vocabulary is stated once in PHP and once in the CHECK that actually enforces it.
            // **Against the TABLE, not a constant.** The icon vocabulary used to be sixteen names
            // in a CHECK; it is 4,185 rows now, and a list that long belongs in neither a constraint
            // nor a class constant. `exists` is the same authority the picker reads from, so the two
            // cannot disagree.
            'icon' => ['nullable', Rule::exists('icons', 'name')],
            'colour' => ['nullable', Rule::in(Location::COLOURS)],
        ];
    }
}
