<?php

namespace App\Models\Scopes;

use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Scope;
use Illuminate\Support\Facades\Auth;

/**
 * Narrows every query on a tenant table to the authenticated user's current team.
 *
 * ### An unauthenticated query returns nothing, and that is deliberate
 *
 * The obvious alternative is to skip the constraint when there is no user, which reads as
 * harmless and is the opposite: a forgotten `auth()` check would then return EVERY tenant's rows
 * rather than none. Failing closed means the worst case of a missing guard is an empty list, which
 * is a bug someone reports, instead of a leak nobody sees.
 *
 * The console is the one place this bites honestly: a `php artisan tinker` session or a seeder has
 * no authenticated user and will see nothing until it removes the scope by name. That is the
 * intended friction.
 *
 * ### Cross-tenant reads look like absence, not refusal
 *
 * Because the scope applies inside the query rather than after it, another tenant's row is not
 * found at all. A controller's `findOrFail` therefore answers 404 and never 403, which is the
 * second tenancy rule: a 403 confirms that an identifier exists and lets a tenant enumerate
 * another tenant's rows one request at a time.
 */
final class TeamScope implements Scope
{
    /**
     * Constrain the query to the current team.
     */
    public function apply(Builder $builder, Model $model): void
    {
        $builder->where(
            $model->qualifyColumn('team_id'),
            self::currentTeamId(),
        );
    }

    /**
     * The authenticated user's current team, or null when there is no user.
     *
     * Null is a real value here rather than an error: it makes the scope match nothing, which is
     * the failing-closed behaviour described above. Callers that need to distinguish "no tenant"
     * from "empty tenant" should check `Auth::check()` themselves and say what they mean.
     */
    public static function currentTeamId(): int|string|null
    {
        $user = Auth::user();

        if ($user === null) {
            return null;
        }

        return $user->getAttribute('current_team_id');
    }
}
