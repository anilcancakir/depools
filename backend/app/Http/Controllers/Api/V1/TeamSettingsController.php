<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Scopes\TeamScope;
use App\Models\Team;
use App\Models\Unit;
use App\Rules\UnitExists;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * The settings that belong to a TEAM rather than to a person or a device.
 *
 * **The distinction is what decides where a setting lives, and it is not stylistic.** The assistant
 * toggle and the placement dial sit in `AppPreferences`, in magic's local cache, because they are
 * per-user and per-device: the worst case of losing one is re-picking it. A default unit cannot be
 * there, because it decides what the SERVER writes when a product arrives without one, so a
 * client-side copy would not reach a product created by the assistant, a scan batch or an import.
 *
 * ### No team id in, or out
 *
 * The team is the authenticated one, always. `TeamScope::currentTeamId()` resolves it, and no route
 * here takes a team parameter, which is the surest way to keep one out: a parameter that does not
 * exist cannot be tampered with. That is the same rule every other endpoint in this app follows.
 */
final class TeamSettingsController extends Controller
{
    public function show(): JsonResponse
    {
        return response()->json(['data' => $this->payload($this->team())]);
    }

    public function update(Request $request): JsonResponse
    {
        $data = $request->validate([
            // **`nullable` is a real value here, not an absent one:** clearing the default is how a
            // team goes back to the vocabulary's own fallback, so `null` has to be accepted and
            // written rather than treated as "no change".
            'default_unit' => ['present', 'nullable', 'string', 'max:16', new UnitExists],
        ]);

        $team = $this->team();

        $code = $data['default_unit'];
        $team->default_unit_id = $code === null
            ? null
            : Unit::query()->visibleTo($team->getKey())->where('code', $code)->value('id');

        $team->save();

        return response()->json(['data' => $this->payload($team->refresh())]);
    }

    /**
     * The authenticated team, or a 404 when there is none.
     *
     * A user with no current team is not an error state worth a special message: every other
     * endpoint answers nothing for them because the scope matches nothing, and this one says the
     * same thing in the same way.
     */
    private function team(): Team
    {
        return Team::query()->findOrFail(TeamScope::currentTeamId());
    }

    /**
     * @return array<string, mixed>
     */
    private function payload(Team $team): array
    {
        // The CODE, not the id. Everything else in this API speaks unit codes, and a client that had
        // to hold a uuid to name a unit would be the only place that does.
        return [
            'default_unit' => $team->default_unit_id === null
                ? null
                : Unit::query()->whereKey($team->default_unit_id)->value('code'),
        ];
    }
}
