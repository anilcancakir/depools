<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTeam;
use FlutterSdk\MagicStarter\Support\ConditionallyUsesUuids;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Carbon;

/**
 * Every credit that arrives. The grant half of a balance that is never stored (D106).
 *
 * Same shape as the stock ledger and for the same reason: a written number cannot be audited. The
 * monthly reset is not a job that zeroes a column, it is an allowance grant reaching its `expires_at`
 * while a top-up, which belongs to no period and never expires, stays. Nothing has to run on time for
 * the balance to be right, which is the property a counter column cannot have.
 */
final class AiCreditGrant extends Model
{
    use BelongsToTeam;
    use ConditionallyUsesUuids;

    protected $fillable = [
        'kind',
        'credits',
        'period_start',
        'expires_at',
        'payment_id',
        'granted_by',
        'note',
    ];

    protected function casts(): array
    {
        return [
            'credits' => 'integer',
            'period_start' => 'datetime',
            'expires_at' => 'datetime',
        ];
    }

    /**
     * Grants that still count toward a balance right now.
     *
     * A null `expires_at` means it never expires, which is a top-up's normal state rather than a
     * missing value, so it has to be included explicitly: `where('expires_at', '>', now())` alone
     * silently drops every top-up ever bought.
     */
    public function scopeUnexpired(Builder $query, ?Carbon $at = null): Builder
    {
        $at ??= Carbon::now();

        return $query->where(static function (Builder $q) use ($at): void {
            $q->whereNull('expires_at')->orWhere('expires_at', '>', $at);
        });
    }
}
