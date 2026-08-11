<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTeam;
use App\Models\Concerns\NormalisesName;
use App\Models\Scopes\TeamScope;
use FlutterSdk\MagicStarter\Support\ConditionallyUsesUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\SoftDeletes;
use RuntimeException;

/**
 * A thing the tenant holds. Carries no quantity.
 *
 * Quantity is the sum of the ledger, materialised for reads. Asking a product how much there is
 * has to go through its lots or through `product_stock`, and that indirection is the point: it is
 * what makes consumption rate, stockout prediction and waste measurement possible at all.
 */
final class Product extends Model
{
    use BelongsToTeam;
    use ConditionallyUsesUuids;
    use HasFactory;
    use NormalisesName;
    use SoftDeletes;

    /** @var list<string> */
    protected $fillable = [
        'name',
        'brand',
        'description',
        'sku',
        'image_path',
        'base_unit',
        'tracks_expiry',
        'default_shelf_life_days',
        'opened_shelf_life_days',
        'content_amount',
        'content_unit',
        'tracking_mode',
        'par_level',
        'reorder_point',
    ];

    protected function casts(): array
    {
        return [
            'tracks_expiry' => 'boolean',
            'content_amount' => 'decimal:3',
            'par_level' => 'decimal:3',
            'reorder_point' => 'decimal:3',
        ];
    }

    /**
     * Invariant 8's transition half, which no CHECK can reach because it needs another table.
     *
     * ### The rule is asymmetric, and the asymmetry is the whole content of it
     *
     * **`serial -> lot` is refused as soon as one serial row exists**, which is permanent in
     * practice: a released serial is KEPT rather than deleted, so the first serial a product ever
     * held closes that direction for good. There is nothing to collapse those rows into. A serial is
     * one physical drill with its own warranty and its own history, and a fungible quantity of four
     * cannot say which four.
     *
     * **`lot -> serial` is refused only while a lot still HOLDS something.** An emptied lot is
     * history in a mechanism the product no longer uses, and history is not a reason to block a
     * correction: a user who set a power tool up as lot-tracked, received it, sold it, and then
     * realised each unit needs its own serial should be able to fix the product rather than abandon
     * it and start a second one. Refusing here would also spend a unique-SKU slot, which is what D4
     * meters.
     *
     * The exception is deliberate rather than a validation rule, because `update`, `fill` and a
     * Filament action all reach the model and only one of them would reach a request validator.
     */
    protected static function booted(): void
    {
        self::updating(static function (self $product): void {
            if (! $product->isDirty('tracking_mode')) {
                return;
            }

            // Both checks are scope-free for the same reason the derivations below are: the product is
            // the boundary. Under `TeamScope` a console or queue path would see no serials and no
            // lots, and the guard would permit exactly the transition it exists to refuse.
            if ($product->tracking_mode === 'lot' && $product->serials()->withoutGlobalScope(TeamScope::class)->exists()) {
                throw new RuntimeException(
                    'A product that has held serials cannot return to lot tracking: an individually '
                    .'identified unit has no fungible quantity to collapse into.',
                );
            }

            if ($product->tracking_mode === 'serial'
                && $product->lots()->withoutGlobalScope(TeamScope::class)->where('remaining_quantity', '>', 0)->exists()) {
                throw new RuntimeException(
                    'A product cannot switch to serial tracking while its lots still hold stock: '
                    .'consume or transfer the remaining quantity out first.',
                );
            }
        });
    }

    /**
     * Every batch of this product, including closed ones.
     *
     * Closed lots stay because they are the evidence behind the consumption history; hiding them
     * would make the ledger look incomplete to anyone auditing it.
     */
    public function lots(): HasMany
    {
        return $this->hasMany(StockLot::class);
    }

    /**
     * The tenant's cross-cutting labels on this product.
     */
    public function tags(): BelongsToMany
    {
        return $this->belongsToMany(Tag::class, 'product_tag')
            ->using(ProductTag::class)
            ->withTimestamps()
            ->orderBy('tags.name');
    }

    /**
     * Set this product's tags from names, creating only the tags whose fold is genuinely new.
     *
     * The sanctioned way in, and the reason it exists rather than leaving callers to `attach()`:
     *
     * - a raw `attach()` would insert a pivot row with a null `team_id`, which the column refuses. The
     *   pivot is a row in a tenant table rather than a tenant model, so nothing stamps it automatically.
     * - a caller resolving tags itself would eventually match on `name` instead of on the fold, and the
     *   canonical set that makes the chip row readable would quietly stop being canonical.
     *
     * `sync` rather than `attach`, because the tag editor sends the full set the product should end up
     * with: an enrichment pass that returns two tags for a product that had three is REPLACING them, and
     * additive semantics would make removing a wrong tag impossible from that path.
     *
     * @param  list<string>  $names
     */
    public function syncTags(array $names): void
    {
        $ids = [];

        foreach ($names as $name) {
            $tag = Tag::findOrCreateFor($name);
            $ids[$tag->getKey()] = ['team_id' => $this->team_id];
        }

        $this->tags()->sync($ids);
    }

    /**
     * Every individually identified unit, including released ones.
     *
     * Empty for a lot-tracked product, and holding the product's entire quantity for a serial-tracked
     * one (invariant 9). The two are never both populated with stock, which is invariant 8.
     */
    public function serials(): HasMany
    {
        return $this->hasMany(ProductSerial::class);
    }

    /**
     * The materialised per-location totals.
     *
     * The list screen's only source for quantity. Eager-loaded by the index endpoint so fifty
     * products cost one extra query rather than fifty aggregations over the ledger.
     */
    public function stock(): HasMany
    {
        return $this->hasMany(ProductStock::class);
    }

    /**
     * Every movement that touched this product.
     */
    public function movements(): HasMany
    {
        return $this->hasMany(StockMovement::class);
    }

    /**
     * The current quantity, summed from the ledger rather than read from a column.
     *
     * Slow by construction and correct by construction. `product_stock` exists so list screens do
     * not call this per row; this is what that table is checked AGAINST, and per invariant 1 the
     * ledger wins any disagreement.
     */
    public function quantityFromLedger(): string
    {
        // Fixed to the schema's own scale, and that is a correctness fix rather than cosmetics.
        //
        // `sum()` returns whatever the driver hands back: PostgreSQL sums `numeric(12,3)` into an
        // exact `numeric` and PDO gives the string `'11.000'`, while SQLite gave `11`. So this
        // method's return value used to depend on the database, and invariant 1's test was pinning
        // one driver's formatting rather than the invariant.
        //
        // `bcadd` rather than `number_format`, because the latter routes an exact decimal through a
        // float on its way to a string, which is the one thing a quantity must not do. Three places
        // matches `decimal(12,3)` and matches `stock_lots.remaining_quantity`'s own cast, so the two
        // numbers an audit compares by hand are formatted alike.
        // Scope-free for the reason `StockLedger`'s docblock records: this product is the tenancy
        // boundary, and under `TeamScope` the nightly sweep would compare a real projection against
        // a sum over nothing and report every row in the database as drifted.
        return bcadd(
            (string) $this->movements()->withoutGlobalScope(TeamScope::class)->sum('delta'),
            '0',
            3,
        );
    }
}
