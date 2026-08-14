<?php

namespace App\Models;

use App\Models\Scopes\TeamScope;
use FlutterSdk\MagicStarter\Support\ConditionallyUsesUuids;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * A unit stock can be counted in: a seeded UN/ECE Rec 20 row, or a tenant's own word.
 *
 * Replaces `products.base_unit` as a free `string(16)`, which made `kg`, `KG` and `kilogram` three
 * different units and printed a stored code straight at the user.
 *
 * The migration carries the reasoning: why Rec 20 codes, why no dimensional category, and why the
 * foreign key points at `id` rather than at `code`.
 *
 * Deliberately does NOT use the `BelongsToTeam` concern every other tenant-owned model does; the scope
 * below says why. Named in prose rather than as a `@see`, because importing a class only so a docblock
 * can point at it leaves an unused import that static analysis is right to flag.
 */
final class Unit extends Model
{
    use ConditionallyUsesUuids;

    /**
     * The unit a product falls back to when nothing has said otherwise.
     *
     * `C62` is Rec 20 for one piece, and it is the countable answer most of a delivery wants. Named
     * here because the seeder, the product default and the batch create path all mean this one row,
     * and three literals is how the previous vocabulary ended up disagreeing with itself.
     */
    public const DEFAULT_CODE = 'C62';

    /**
     * A tenant's own code, in the one shape the vocabulary will hold it.
     *
     * **Upper-cased and trimmed, because otherwise the free-text hole comes back through the side
     * door.** `koli`, `Koli` and ` KOLI ` are one word a person typed three ways, and without folding
     * they would be three rows and three units, which is exactly what `kg`, `KG` and `kilogram` were.
     * The seeded codes are upper case already, so a tenant's own sit in the same space and a collision
     * with `CT` or `CS` is detectable rather than silent.
     *
     * The NAME keeps whatever they typed. The code is an identifier and the name is their word for it.
     */
    public static function normaliseCode(string $code): string
    {
        return mb_strtoupper(trim($code));
    }

    /**
     * **`team_id` is deliberately absent**, which `backend.md` states as a rule for every model and
     * which matters more here than anywhere: on this table a null `team_id` does not mean "unstamped",
     * it means SHARED. So a mass-assigned `team_id` silently dropped would not fail on a NOT NULL
     * column, it would publish one tenant's word to every tenant. `ProductCategory` does list it, and
     * that is the shape this followed at first; the rule is right and the precedent is not.
     *
     * Writers set it explicitly with `setAttribute` before saving, the same way `BelongsToTeam`,
     * `StockWriter` and `StockLedger` all do.
     *
     * @var list<string>
     */
    protected $fillable = [
        'reference_unit_id',
        'code',
        'name',
        'factor',
    ];

    /**
     * A unit belonging to a team, with the owner set the one way this model accepts.
     *
     * Named rather than left to each caller, because "set `team_id` outside `fill`" is exactly the
     * instruction that gets followed nine times out of ten, and the tenth creates a shared unit.
     *
     * @param  array<string, mixed>  $attributes
     */
    public static function createFor(string $teamId, array $attributes): self
    {
        $unit = new self($attributes);
        $unit->setAttribute('team_id', $teamId);
        $unit->save();

        return $unit;
    }

    protected function casts(): array
    {
        return [
            'factor' => 'decimal:6',
        ];
    }

    /**
     * Shared rows plus the current tenant's own, which is what every read of this table means.
     *
     * **Deliberately not the global `BelongsToTeam` scope**, for the reason `ProductCategory` records:
     * that scope asserts `team_id = current` and would hide every seeded row, because a shared unit
     * carries `team_id = NULL`. Cross-tenant leakage is still impossible, since the only rows this
     * admits beyond the tenant's own are the ones with no tenant at all.
     */
    public function scopeVisibleTo(Builder $query, ?string $teamId): Builder
    {
        return $query->where(
            fn (Builder $q): Builder => $q->whereNull('team_id')->orWhere('team_id', $teamId)
        );
    }

    /** Only the seeded vocabulary, with no tenant's own words in it. */
    public function scopeShared(Builder $query): Builder
    {
        return $query->whereNull('team_id');
    }

    /**
     * The unit a code names, or null when this tenant can see no such unit.
     *
     * **The ONE lookup**, and it is here rather than in a service because three different callers need
     * the same answer for different reasons: the validation rule turns a null into a 422, the model's
     * own mutator turns it into a `RuntimeException` (the boundary already validated, so a null there
     * is a programming error rather than a user's), and a reader wants the row. Three implementations
     * of "find the unit for this code" is how the previous vocabulary ended up with two disagreeing
     * defaults.
     */
    public static function findByCode(?string $code): ?self
    {
        $code = self::normaliseCode((string) $code);

        if ($code === '') {
            return null;
        }

        return self::query()
            ->visibleTo(TeamScope::currentTeamId())
            ->where('code', $code)
            ->first();
    }

    /**
     * The countable unit, which is what most of a delivery is.
     *
     * `sole()` rather than `first()`: this row is inserted by the units migration precisely so it
     * cannot be missing, and a null here would mean a database that never ran it. Failing at the
     * lookup names the cause; failing later on a NOT NULL foreign key does not.
     */
    public static function fallback(): self
    {
        return self::query()->shared()->where('code', self::DEFAULT_CODE)->sole();
    }

    /** What this unit is a multiple of, when it is a multiple of anything. */
    public function reference(): BelongsTo
    {
        return $this->belongsTo(self::class, 'reference_unit_id');
    }

    /** The units defined in terms of this one. */
    public function derived(): HasMany
    {
        return $this->hasMany(self::class, 'reference_unit_id');
    }

    /** Products counted in this unit. */
    public function products(): HasMany
    {
        return $this->hasMany(Product::class, 'base_unit_id');
    }

    /**
     * How many of the chain's ROOT unit one of these equals.
     *
     * The root rather than the immediate reference, which the old name (`factorToReference`) got wrong:
     * `MGM` points at `GRM` with `0.001` and `GRM` points at `KGM` with the same, so a milligram is
     * `0.000001` kilograms and the useful answer is the product of the whole walk.
     *
     * Walks up rather than storing an absolute factor, which is the shape Odoo moved to when it dropped
     * categories: an absolute column has to be recomputed for every descendant whenever a ratio
     * changes, and D25 already forbids editing a ratio in place for exactly that reason (SAP's
     * documented failure, where changing a factor silently re-derives history).
     *
     * The seeded data is three deep at most (`MGM` to `GRM` to `KGM`). The hop guard is for a tenant who
     * relates their own unit to a derived one, and for the case a reference cycle should be impossible
     * but a bug made one anyway: the CHECK forbids a self-reference and nothing forbids a longer loop.
     */
    public function factorToRoot(): float
    {
        $factor = 1.0;
        $unit = $this;
        $hops = 0;

        while ($unit->reference_unit_id !== null && $hops < 8) {
            $factor *= (float) $unit->factor;
            $unit = $unit->reference;

            if ($unit === null) {
                break;
            }

            $hops++;
        }

        return $factor;
    }
}
