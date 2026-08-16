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
     * The unit a product in this category is most likely counted in, or null for the ordinary case.
     *
     * ### Five entries, not 5,595
     *
     * D32 says `base_unit` is inferred "from the name, from the category, and failing both it is
     * editable". A row per node is not hand-authorable and would be mostly wrong anyway: the
     * countable default is right for the overwhelming majority of the taxonomy, so what is worth
     * mapping is the small set of branches where it is WRONG.
     *
     * The five below are the food branches sold by weight. Everything else, including the ones that
     * look like they belong here, is deliberately absent:
     *
     * - **Beverages** is bottles and cartons, which are counted.
     * - **Dairy** is cartons and tubs.
     * - **Bakery** and **Snack Foods** are packets.
     * - **Eggs** is counted, which is exactly why `Meat, Seafood & Eggs` is not mapped as a whole
     *   and its Meat and Seafood children are mapped individually. Google's own grouping bundles a
     *   counted thing with two weighed ones.
     *
     * ### Matched by path prefix rather than by walking parents
     *
     * `path` is materialised, so a descendant carries its ancestors in the string and one comparison
     * answers for the whole branch: `Fruits & Vegetables > Fresh & Frozen Vegetables > Carrots`
     * resolves without loading a single parent row.
     *
     * The boundary matters. A bare `str_starts_with` would let a future `Fruits & Vegetables Extra`
     * inherit from a branch it does not belong to, so the comparison is the path itself or the path
     * plus the separator.
     */
    public function defaultUnitCode(): ?string
    {
        foreach (self::WEIGHED_BRANCHES as $branch => $code) {
            if ($this->path === $branch || str_starts_with((string) $this->path, $branch.' > ')) {
                return $code;
            }
        }

        return null;
    }

    /**
     * The branches whose products are weighed, and what they are weighed in.
     *
     * Keyed by PATH rather than by `google_id`, which is the opposite of what D87 says about the
     * stable key, and the reason is that this map has to survive a database with no taxonomy in it:
     * a test that creates one category should be able to exercise the mapping without the seed. The
     * `google_id` is in the comment beside each so a renamed path can be traced back.
     *
     * `KGM` is Rec 20's kilogram, which the units table seeds.
     */
    private const WEIGHED_BRANCHES = [
        // 4628
        'Food, Beverages & Tobacco > Food Items > Meat, Seafood & Eggs > Meat' => 'KGM',
        // 4629
        'Food, Beverages & Tobacco > Food Items > Meat, Seafood & Eggs > Seafood' => 'KGM',
        // 430
        'Food, Beverages & Tobacco > Food Items > Fruits & Vegetables' => 'KGM',
        // 431
        'Food, Beverages & Tobacco > Food Items > Grains, Rice & Cereal' => 'KGM',
        // 433
        'Food, Beverages & Tobacco > Food Items > Nuts & Seeds' => 'KGM',
    ];

    /**
     * The label for a locale, falling back to English rather than to nothing.
     *
     * `name_tr` is the nullable one: a tenant typing a single name fills the required English
     * column, whatever language they typed it in, and storing it in `name_tr` as well would be
     * calling it a translation. So the fallback is explicit and lives here rather than in each view.
     *
     * The direction reversed with the column: this used to fall back to Turkish, from a migration
     * written when the product was Turkey-first.
     */
    public function label(string $locale): string
    {
        return $locale === 'tr'
            ? ($this->name_tr ?? $this->name_en)
            : $this->name_en;
    }
}
