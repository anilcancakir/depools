<?php

namespace App\Models\Concerns;

use App\Models\Scopes\TeamScope;
use App\Models\Team;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Tenancy for every business table.
 *
 * The team is resolved from the AUTH CONTEXT and from nowhere else. It is never read from a
 * request parameter, a route binding, a tool argument or an MCP call argument, and that is the
 * single rule in `docs/depools-system/data-model.md` marked non-negotiable. It is the exact
 * failure that leaked data across roughly a thousand organisations in Asana's MCP incident in
 * 2025, where the tenant identifier arrived as an argument and went unchecked for over a month.
 *
 * Two halves, and both are needed:
 *
 * - A global scope narrows every read to the current team, so a forgotten `where` cannot leak.
 * - A creating hook stamps `team_id` on write, so a forgotten assignment cannot orphan a row into
 *   another tenant or into none.
 *
 * The scope is deliberately NOT removable through the usual `withoutGlobalScope` convenience on
 * application code paths. Where a genuine cross-tenant read is required (a queue worker rebuilding
 * a materialised total, say), the caller states it explicitly and a test covers it.
 */
trait BelongsToTeam
{
    /**
     * Register the tenancy scope and the write-side stamp.
     *
     * Laravel calls this automatically for a trait named `boot{TraitName}`.
     */
    public static function bootBelongsToTeam(): void
    {
        static::addGlobalScope(new TeamScope);

        static::creating(static function (self $model): void {
            // Only when absent, so a seeder or a deliberate cross-tenant write still works. A
            // request path never sets it, so the resolver below is what applies in practice.
            if ($model->getAttribute('team_id') === null) {
                $model->setAttribute('team_id', TeamScope::currentTeamId());
            }
        });
    }

    /**
     * The owning team.
     */
    public function team(): BelongsTo
    {
        return $this->belongsTo(Team::class);
    }
}
