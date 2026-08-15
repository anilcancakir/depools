<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTeam;
use App\Models\Concerns\HasStoredImage;
use App\Models\Scopes\TeamScope;
use FlutterSdk\MagicStarter\Support\ConditionallyUsesUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\SoftDeletes;
use Illuminate\Support\Facades\DB;
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
    use HasStoredImage;
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
        // D119. `image_path` is absent on purpose, exactly as it is on `ProductImage`: a path is
        // written by the endpoint that stored the bytes, never taken from a request, or a caller
        // could point a location at any file on the disk.
        'icon',
        'colour',
    ];

    /**
     * The icons a location may carry, matching the CHECK on the column.
     *
     * **A closed catalogue of NAMES, and the reason is the build rather than taste.** Storing a
     * Material codepoint and rebuilding an `IconData` from it is the obvious shape;
     * `--tree-shake-icons` defaults to ON, so a glyph no constant references is dropped from the font
     * and the user's own location renders as tofu. The client maps each of these to a `const`.
     */
    public const ICONS = [
        'home', 'kitchen', 'fridge', 'freezer', 'pantry', 'cupboard',
        'shelf', 'drawer', 'box', 'basket', 'crate', 'warehouse',
        'garage', 'basement', 'office', 'van',
    ];

    /**
     * The colours a location may carry, matching the CHECK on the column.
     *
     * Named by hue rather than by role, because the user picks one from a swatch: "which of my
     * shelves is the primary one" is a riddle. Each resolves to a token pair in the client, so the
     * value is a key rather than a colour, and `bin/design-tokens` would refuse a raw hex anyway.
     */
    public const COLOURS = [
        'slate', 'blue', 'teal', 'green', 'amber', 'red', 'violet',
    ];

    /**
     * A location's photograph is written to the media disk, not the application default.
     *
     * Without this the accessor would build a url for `filesystems.default` while `storeImage` wrote
     * to `media.images.disk`. The two coincide on the current configuration and stop the moment
     * either moves, which is the kind of agreement that is worth stating rather than relying on.
     */
    protected function imageDisk(): ?string
    {
        return config('media.images.disk');
    }

    /**
     * Keep `path` and `depth` true on every write, for this row AND everything under it.
     *
     * The cascade is triggered by `path` having actually changed rather than by a save happening, which
     * is what makes it both cheap and complete: a no-op rename rewrites nothing, and a real one
     * propagates all the way down because each child's own save changes ITS path and fires its own
     * cascade. Bounded by [MAX_DEPTH] by construction.
     *
     * Before this, only the saved row was re-pathed. Renaming `Mutfak` left every shelf inside it
     * reading `/Mutfak/Buzdolabı/`, so the breadcrumb on screen showed the old room name forever:
     * `getFullPathAttribute` reads `path`, which is the whole point of storing it, and nothing rewrote
     * it. `inventory-core.md` makes renaming a documented flow ("the user renames it later"), so this
     * was a bug waiting on the `update` endpoint rather than a hypothetical.
     */
    protected static function booted(): void
    {
        self::saving(static function (self $location): void {
            $location->refreshHierarchy();
        });

        self::saved(static function (self $location): void {
            if (! $location->wasChanged('path')) {
                return;
            }

            foreach ($location->children()->withoutGlobalScope(TeamScope::class)->get() as $child) {
                $child->save();
            }
        });
    }

    /**
     * Wrapped in a transaction so a subtree is re-pathed completely or not at all.
     *
     * The cascade in [booted] runs inside `parent::save()`, so a descendant that would exceed
     * [MAX_DEPTH] throws from its own check and rolls this move back with it. Without the wrapper the
     * move would already be committed and the tree would be left half re-pathed, which is worse than
     * refusing: a partially rewritten `path` column is indistinguishable from a correct one.
     *
     * That is also what closes the graft hole. Checking the cap only on the row being moved lets a
     * legal-looking move push its subtree past 6, because nobody touched the descendants directly.
     */
    public function save(array $options = []): bool
    {
        return DB::transaction(fn (): bool => parent::save($options));
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
     * The materialised per-product totals sitting here.
     *
     * Read-only, and it exists for one question: does this location hold anything at all. The count
     * screen has to open on a shelf with stock on it, and the first location in reading order is a
     * ROOT, which holds nothing directly because its children do. Measured against the demo tenant,
     * defaulting to it opened the count screen on "nothing at this location" for a tenant with four
     * full shelves.
     *
     * The screen used to answer that from the products it had loaded, which stopped being possible
     * when the product list became one page: a shelf whose stock happens to sit on page three would
     * have read as empty. So the location payload answers it instead, where the answer is exact.
     */
    public function stock(): HasMany
    {
        return $this->hasMany(ProductStock::class);
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
     * ### The parent is resolved without the tenancy scope, and a missing one is refused
     *
     * Both halves were bugs, and both were silent. `TeamScope` fails closed, so outside a request
     * `self::find()` returned null for a perfectly real parent and the code took its "this is a root"
     * branch: measured, a console rename turned a depth-2 shelf into `depth = 0`, `path = /Üst Raf 2/`,
     * while `parent_location_id` stayed set. The row then claimed to be a root AND to have a parent,
     * and every screen reads `path`. Same class as D111, in a second place, except this one wrote wrong
     * data rather than doing nothing.
     *
     * A dangling parent is now REFUSED rather than rooted. The scope-free lookup still excludes a
     * soft-deleted parent, deliberately: keeping `/DeletedRoom/Shelf/` in a breadcrumb is worse than
     * failing. What the policy for a deleted room SHOULD be is undecided (no `destroy` endpoint exists
     * and no feature doc says whether it cascades, reparents or is refused), so this fails loudly and
     * leaves the decision to whoever builds delete, instead of having it made by a fallback branch. A
     * save that RESOLVES the dangling parent still works, so a row is never trapped.
     *
     * @throws RuntimeException when the parent is this location or one of its descendants, when the
     *                          resulting depth would exceed [MAX_DEPTH], or when a named parent cannot
     *                          be found.
     */
    public function refreshHierarchy(): void
    {
        if ($this->parent_location_id === null) {
            $this->path = '/'.$this->name.'/';
            $this->depth = 0;

            return;
        }

        $parent = self::query()
            ->withoutGlobalScope(TeamScope::class)
            ->find($this->parent_location_id);

        if ($parent === null) {
            throw new RuntimeException(
                'This location names a parent that no longer exists. Move it somewhere that does, or '
                .'clear its parent, rather than leaving it pointing at nothing.',
            );
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
     *
     * Scope-free for the reason [refreshHierarchy] records, and here the consequence was that the cycle
     * guard did not work at all outside a request: the walk stopped at the first level it could not
     * resolve, found no cycle, and a root placed inside its own grandchild was ACCEPTED. Measured. That
     * is precisely the MVP failure this whole design exists to prevent, "one location made its own
     * ancestor hung the query", reachable again through a scope rather than through a missing check.
     */
    public function ancestorKeyPath(): string
    {
        $keys = [];
        $node = $this;

        for ($level = 0; $level <= self::MAX_DEPTH && $node !== null; $level++) {
            $keys[] = $node->getKey();

            $node = $node->parent_location_id === null
                ? null
                : self::query()->withoutGlobalScope(TeamScope::class)->find($node->parent_location_id);
        }

        return '/'.implode('/', $keys).'/';
    }
}
