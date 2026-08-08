<?php

declare(strict_types=1);

namespace App\Models;

use App\Models\Concerns\BelongsToTeam;
use FlutterSdk\MagicStarter\Support\ConditionallyUsesUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\SoftDeletes;

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
        return (string) $this->movements()->sum('delta');
    }
}
