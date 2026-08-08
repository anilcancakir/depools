<?php

declare(strict_types=1);

namespace App\Models;

use App\Models\Concerns\BelongsToTeam;
use FlutterSdk\MagicStarter\Support\ConditionallyUsesUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\SoftDeletes;
use RuntimeException;

/**
 * A place stock can be.
 *
 * ### `path` and `depth` are maintained here, not computed by the caller
 *
 * Both are written by this model on save, because a value a caller has to remember to set is a
 * value that will eventually be wrong, and these two carry an invariant each (data-model.md #7).
 * The MVP recomputed the hierarchy by walking `parent_location_id` per read, with no depth limit
 * and no cycle guard: one location made its own ancestor hung the query.
 *
 * ### The cycle guard rejects rather than truncates
 *
 * Attaching a location under one of its own descendants is not a value to clamp, it is a request
 * that cannot be satisfied, so it throws. Silently reparenting to the root would move a user's
 * stock somewhere they did not ask for and they would find out by not finding it.
 */
final class Location extends Model
{
    use BelongsToTeam;
    use ConditionallyUsesUuids;
    use HasFactory;
    use SoftDeletes;

    /**
     * The deepest a hierarchy may go, per data-model.md invariant 7.
     *
     * Six is the deepest legal `depth`, not the count of levels: a root is 0, so a legal tree has
     * seven tiers. `Depo > Kat 2 > Oda 3 > Raf A > Kutu 1 > Çekmece > Bölme` is already deeper than
     * any stockroom anyone described, and a bound is what keeps a prefix query and a breadcrumb
     * both finite.
     */
    public const int MAX_DEPTH = 6;

    /** @var list<string> */
    protected $fillable = [
        'parent_location_id',
        'name',
    ];

    /**
     * Keep `path` and `depth` true on every write.
     */
    protected static function booted(): void
    {
        self::saving(static function (self $location): void {
            $location->refreshHierarchy();
        });
    }

    /**
     * The location this one sits inside, if any.
     */
    public function parent(): BelongsTo
    {
        return $this->belongsTo(self::class, 'parent_location_id');
    }

    /**
     * The locations directly inside this one.
     */
    public function children(): HasMany
    {
        return $this->hasMany(self::class, 'parent_location_id');
    }

    /**
     * The already-joined path a screen renders, e.g. `Mutfak › Buzdolabı`.
     *
     * Derived from `path` rather than by walking parents, which is the whole point of storing it.
     */
    public function getFullPathAttribute(): string
    {
        return str_replace('/', ' › ', trim($this->path ?? $this->name, '/'));
    }

    /**
     * Recompute `path` and `depth` from the parent, rejecting a cycle and an over-deep tree.
     *
     * @throws RuntimeException when the parent is this location or one of its descendants, or when
     *                          the resulting depth would exceed [MAX_DEPTH].
     */
    public function refreshHierarchy(): void
    {
        $parent = $this->parent_location_id === null ? null : self::find($this->parent_location_id);

        if ($parent === null) {
            $this->path = '/'.$this->name.'/';
            $this->depth = 0;

            return;
        }

        // A cycle is a prefix relationship: the candidate parent's path already contains this
        // location's own segment. Checking the stored path costs one string comparison, where
        // walking the chain costs a query per level and is what the MVP did.
        $ownSegment = '/'.$this->getKey().'/';

        if ($this->exists && str_contains($parent->ancestorKeyPath(), $ownSegment)) {
            throw new RuntimeException(
                'A location cannot be placed inside itself or inside one of its own children.',
            );
        }

        $depth = $parent->depth + 1;

        // `>` and not `>=`: data-model.md invariant 7 reads "`locations.depth` never exceeds 6",
        // and `depth` starts at 0 for a root, so 6 is the deepest LEGAL value rather than the first
        // illegal one. The first version rejected 6 as well, which is stricter than the spec and is
        // the kind of off-by-one that only a test written against the wording catches.
        if ($depth > self::MAX_DEPTH) {
            throw new RuntimeException(
                'A location may sit at most '.self::MAX_DEPTH.' levels below the root.',
            );
        }

        $this->path = rtrim($parent->path, '/').'/'.$this->name.'/';
        $this->depth = $depth;
    }

    /**
     * The chain of ancestor KEYS, used only by the cycle guard.
     *
     * `path` holds names, which a user may repeat (`Raf A` under two different rooms), so it cannot
     * answer an identity question. This walks keys, and it is bounded by [MAX_DEPTH] by
     * construction, so the unbounded traversal the MVP had is not reachable here.
     */
    public function ancestorKeyPath(): string
    {
        $keys = [];
        $node = $this;

        for ($level = 0; $level <= self::MAX_DEPTH && $node !== null; $level++) {
            $keys[] = $node->getKey();
            $node = $node->parent_location_id === null ? null : self::find($node->parent_location_id);
        }

        return '/'.implode('/', $keys).'/';
    }
}
