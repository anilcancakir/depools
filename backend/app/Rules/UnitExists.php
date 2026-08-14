<?php

namespace App\Rules;

use App\Models\Unit;
use Closure;
use Illuminate\Contracts\Validation\ValidationRule;

/**
 * The unit code names a row this tenant can see: a seeded Rec 20 unit, or one they added.
 *
 * **A refusal rather than a create**, which is the line between a closed vocabulary and the free text
 * this replaced. Creating the unit on demand would put the hole straight back: a typo would become a
 * vocabulary entry, and `KG`, `Kg` and `kilogram` would be three units again inside a week. A tenant
 * who genuinely needs their own adds it deliberately, which is what `units.team_id` is for.
 *
 * Existence is asked HERE and nowhere else in a request's path. The model's own mutator throws instead
 * of failing softly, because by the time a request reaches it this rule has already run and an unknown
 * code means a seeder or a test naming something that does not exist.
 */
final class UnitExists implements ValidationRule
{
    public function validate(string $attribute, mixed $value, Closure $fail): void
    {
        if (! is_string($value) || Unit::findByCode($value) === null) {
            $fail('The :attribute is not a unit this team can use.');
        }
    }
}
