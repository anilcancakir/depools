<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Scopes\TeamScope;
use App\Models\Unit;
use App\Rules\UnitExists;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

/**
 * The vocabulary a client may offer, and the one way a tenant extends it.
 *
 * **Adding is DELIBERATE, which is the whole difference between this and the free text it replaced.**
 * The old column accepted anything a form sent, so `kg`, `KG` and `kilogram` became three units by
 * accident. Here a tenant who genuinely counts in something the standard does not name says so once, on
 * purpose, and every later product picks that row rather than retyping the word.
 *
 * Shared rows plus the tenant's own, which is what `visibleTo` means. The order puts the countable unit
 * first and then the rest alphabetically, because a picker's first row is the answer most of a delivery
 * wants and the remainder has no meaningful ranking.
 */
final class UnitController extends Controller
{
    public function index(): JsonResponse
    {
        $units = Unit::query()
            ->visibleTo(TeamScope::currentTeamId())
            ->with('reference')
            ->orderByRaw('CASE WHEN code = ? THEN 0 ELSE 1 END', [Unit::DEFAULT_CODE])
            ->orderBy('code')
            ->get();

        return response()->json([
            'data' => $units->map(fn (Unit $unit): array => [
                'code' => $unit->code,
                // Only a tenant's own unit carries one. A shared row's label is a translation in the
                // client's catalogues keyed on the code, because there is no localised unit word to be
                // had from either stack for free.
                'name' => $unit->name,
                // Null for a shared row, present for a tenant's own, which is what lets a client show
                // "mine" separately without asking a second question.
                'is_own' => $unit->team_id !== null,
                'reference_code' => $unit->reference?->code,
                'factor' => (float) $unit->factor,
            ])->all(),
        ]);
    }

    /**
     * Registers a unit of this tenant's own.
     *
     * ### The code is folded and the name is not
     *
     * `Unit::normaliseCode` upper-cases and trims, so `koli`, `Koli` and ` KOLI ` are one row rather than
     * three. Without that the vocabulary would be free text again, reached through a form instead of a
     * column. The NAME keeps whatever they typed, because the code is an identifier and the name is
     * their word for it.
     *
     * ### A collision is a refusal, including with the shared set
     *
     * `(team_id, code)` is unique per tenant, so a tenant may hold `CT` of their own beside the shared
     * `CT`, and then `findByCode` has two rows to choose from and picks by luck. So this refuses a code
     * the shared vocabulary already defines: if the standard has a word for it, that is the word.
     *
     * ### The ratio is optional and asked in the tenant's own terms
     *
     * `reference_code` plus `factor` says "one case is twelve pieces". Optional, because a tenant may
     * genuinely not know or not care, and a unit with no reference is its own root, which the CHECK on
     * the table pins at a factor of exactly 1.
     */
    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'code' => ['required', 'string', 'max:16'],
            'name' => ['required', 'string', 'max:255'],
            // The unit this one is a multiple of, which has to be one this tenant can already see.
            'reference_code' => ['nullable', 'string', 'max:16', new UnitExists],
            // Required WITH a reference and refused without one, because a factor against nothing is a
            // number that cannot be interpreted, and the table's CHECK would refuse the row anyway with
            // a constraint violation rather than a sentence.
            //
            // `Rule::prohibitedIf` rather than a `prohibited_without` string, which does not exist:
            // Laravel ships `prohibited`, `prohibited_if`, `prohibited_unless` and `prohibits`, and the
            // invented one fails as `Method validateProhibitedWithout does not exist` at request time
            // rather than as anything a reader would spot.
            'factor' => [
                'nullable',
                'numeric',
                'gt:0',
                'required_with:reference_code',
                Rule::prohibitedIf(fn (): bool => ! $request->filled('reference_code')),
            ],
        ]);

        $code = Unit::normaliseCode($data['code']);
        $teamId = TeamScope::currentTeamId();

        // **A null team would write a SHARED row, which is a tenant extending the global vocabulary.**
        // `units.team_id` is nullable because that is how a seeded row says "everybody's", so unlike
        // every other write in this API a missing team does not fail on a NOT NULL column here: it
        // succeeds and puts a tenant's word in front of every other tenant. `TeamScope` returns null for
        // an authenticated user with no `current_team_id`, so the guard is explicit rather than implied.
        if ($teamId === null) {
            abort(403, 'A unit belongs to a team, and this account has none selected.');
        }

        if ($code === '') {
            throw ValidationException::withMessages(['code' => 'A unit needs a code.']);
        }

        $existing = Unit::query()->visibleTo($teamId)->where('code', $code)->first();

        if ($existing !== null) {
            throw ValidationException::withMessages([
                'code' => $existing->team_id === null
                    ? "{$code} is already a standard unit."
                    : "You already have a unit called {$code}.",
            ]);
        }

        $reference = Unit::findByCode($data['reference_code'] ?? null);

        // `createFor` rather than `create`, because `team_id` is not fillable on this model: passing it
        // through `fill` would be silently dropped, and a null `team_id` here does not mean unstamped,
        // it means SHARED.
        $unit = Unit::createFor($teamId, [
            'code' => $code,
            'name' => trim($data['name']),
            'reference_unit_id' => $reference?->getKey(),
            // 1 without a reference, which is what the CHECK requires of a root.
            'factor' => $reference === null ? 1 : $data['factor'],
        ]);

        return response()->json([
            'data' => [
                'code' => $unit->code,
                'name' => $unit->name,
                'is_own' => true,
                'reference_code' => $reference?->code,
                'factor' => (float) $unit->factor,
            ],
        ], 201);
    }
}
