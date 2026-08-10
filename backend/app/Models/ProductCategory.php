<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTeam;
use FlutterSdk\MagicStarter\Support\ConditionallyUsesUuids;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * A node in the shared taxonomy, or a tenant's own.
 *
 * The taxonomy exists so `location_category_affinity` has a vocabulary that spans tenants: the count of
 * category-`c` items already in a location IS the placement suggestion and its explanation (D9), and it
 * produces nothing at cold start unless two tenants can mean the same category.
 *
 * @see BelongsToTeam for the ordinary tenant scope this table deliberately does NOT use
 */
final class ProductCategory extends Model
{
    use ConditionallyUsesUuids;

    /** @var list<string> */
    protected $fillable = [
        'team_id',
        'parent_id',
        'google_id',
        'name_tr',
        'name_en',
        'path',
        'depth',
    ];

    protected function casts(): array
    {
        return [
            'google_id' => 'integer',
            'depth' => 'integer',
        ];
    }

    /**
     * Shared rows plus the current tenant's own, which is what every read of this table means.
     *
     * **Deliberately not the global `BelongsToTeam` scope.** That scope asserts `team_id = current`, and
     * it would hide the entire Google seed, because a shared row carries `team_id = NULL`. A tenant
     * browsing categories has to see both, and the alternative is every call site remembering to
     * `orWhereNull`, which is the kind of thing that is remembered nine times out of ten.
     *
     * Cross-tenant leakage is still impossible: the only rows this admits beyond the tenant's own are
     * the ones with no tenant at all.
     */
    public function scopeVisibleTo(Builder $query, ?string $teamId): Builder
    {
        return $query->where(
            fn (Builder $q): Builder => $q->whereNull('team_id')->orWhere('team_id', $teamId)
        );
    }

    /** Only the shared taxonomy, which is what cross-tenant signal may be computed from. */
    public function scopeShared(Builder $query): Builder
    {
        return $query->whereNull('team_id');
    }

    public function parent(): BelongsTo
    {
        return $this->belongsTo(self::class, 'parent_id');
    }

    public function children(): HasMany
    {
        return $this->hasMany(self::class, 'parent_id');
    }

    public function products(): HasMany
    {
        return $this->hasMany(Product::class);
    }

    /**
     * The label for a locale, falling back to Turkish rather than to nothing.
     *
     * `name_en` is nullable because a tenant typing one name fills only `name_tr`, and storing that
     * Turkish string in the English column would be calling it a translation. So the fallback is
     * explicit and lives here rather than in each view.
     */
    public function label(string $locale): string
    {
        return $locale === 'en'
            ? ($this->name_en ?? $this->name_tr)
            : $this->name_tr;
    }
}
