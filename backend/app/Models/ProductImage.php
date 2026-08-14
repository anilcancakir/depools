<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTeam;
use FlutterSdk\MagicStarter\Support\ConditionallyUsesUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Facades\URL;

/**
 * One picture in a product's gallery.
 *
 * The migration carries the reasoning: why a row is either ours (`path`) or somebody else's
 * (`remote_url`) and never both, why one primary per product is a partial unique index rather than a
 * promise, and why `position` is not unique.
 */
final class ProductImage extends Model
{
    use BelongsToTeam;
    use ConditionallyUsesUuids;

    /**
     * How many pictures one product may hold.
     *
     * A ceiling rather than a guess at what a user needs: without one, a gallery is an unbounded
     * upload target on a tenant's disk quota, and the detail screen's strip stops being scannable
     * long before storage becomes the complaint. Eight covers the front, the back, the label, the
     * shelf and still leaves room.
     */
    public const MAX_PER_PRODUCT = 8;

    /**
     * Where a picture may come from, matching the CHECK on the column.
     *
     * `upload` is the user's own file, `catalogue` a copy of our own shared row, `link` an address
     * supplied rather than copied, `scan` a picture taken while scanning a barcode.
     */
    public const SOURCES = ['upload', 'catalogue', 'link', 'scan'];

    /**
     * `team_id` is absent on purpose, as on every tenant-owned model here.
     *
     * It is stamped by [BelongsToTeam] from the auth context. Fillable would mean a request could name
     * a team, which is the one thing `AGENTS.md` marks non-negotiable.
     *
     * `is_primary` is absent too, and for a different reason: setting it is not a field assignment but
     * a swap, because at most one row per product may carry it. [Product::makeImagePrimary] owns that.
     */
    protected $fillable = [
        'product_id',
        'path',
        'remote_url',
        'attribution',
        'source',
        'position',
    ];

    protected function casts(): array
    {
        return [
            'is_primary' => 'boolean',
            'position' => 'integer',
        ];
    }

    public function product(): BelongsTo
    {
        return $this->belongsTo(Product::class);
    }

    /**
     * The address a client can load, whichever half of the row holds it.
     *
     * `URL::to` around `Storage::url` for the same measured reason `HasStoredImage` carries it: with
     * `FILESYSTEM_DISK=local` and no `url` key on that disk, `Storage::url` answers `/storage/<path>`,
     * a root-relative string that a Flutter mobile build refuses with `No host specified in URI` and a
     * web build resolves against its own origin. An already-absolute url passes through untouched, so
     * `public` and `s3` are unaffected, and so is a `remote_url` that never went near a disk.
     */
    public function getUrlAttribute(): ?string
    {
        $remote = $this->remote_url;

        if (is_string($remote) && trim($remote) !== '') {
            return $remote;
        }

        $path = $this->path;

        if (! is_string($path) || trim($path) === '') {
            return null;
        }

        return URL::to(Storage::url($path));
    }
}
