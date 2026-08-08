<?php

declare(strict_types=1);

namespace App\Models;

use App\Models\Concerns\BelongsToTeam;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * The materialised total for one (product, location) pair.
 *
 * Read-only from the application's point of view: every write goes through
 * [StockLedger::rebuildProductStock]. Nothing here is authored, and a setter on this model would be
 * a way to make the ledger and the totals disagree.
 */
final class ProductStock extends Model
{
    use BelongsToTeam;

    protected $table = 'product_stock';

    /** Only `updated_at`, because a derived row has no meaningful creation moment. */
    public const CREATED_AT = null;

    /** @var list<string> */
    protected $fillable = [
        'product_id',
        'location_id',
        'quantity',
        'earliest_expires_at',
        'lots_count',
    ];

    protected function casts(): array
    {
        return [
            'quantity' => 'decimal:3',
            'earliest_expires_at' => 'date',
        ];
    }

    public function product(): BelongsTo
    {
        return $this->belongsTo(Product::class);
    }

    public function location(): BelongsTo
    {
        return $this->belongsTo(Location::class);
    }
}
