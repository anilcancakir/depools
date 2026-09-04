<?php

namespace App\Http\Requests;

use App\Rules\UnitExists;
use App\Support\ValidationBounds;
use Illuminate\Foundation\Http\FormRequest;

/**
 * `PUT api/v1/team/settings`'s rule set: the settings that belong to a TEAM rather than to a person
 * or a device.
 *
 * **A bare `true`, not a `Gate` call.** A cross-tenant read here answers 404, not 403 (see
 * `TeamScope`), and `FormRequest::failedAuthorization()` throws `AuthorizationException`, which the
 * handler maps to 403. There are zero `Gate::`/`$this->authorize()` calls in any controller today,
 * so an authorization check belongs nowhere in this class.
 */
final class UpdateTeamSettingsRequest extends FormRequest
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
            // **`nullable` is a real value here, not an absent one:** clearing the default is how a
            // team goes back to the vocabulary's own fallback, so `null` has to be accepted and
            // written rather than treated as "no change".
            'default_unit' => ['present', 'nullable', 'string', 'max:'.ValidationBounds::UNIT_CODE_MAX, new UnitExists],
        ];
    }
}
