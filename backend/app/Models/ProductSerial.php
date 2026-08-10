<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTeam;
use FlutterSdk\MagicStarter\Support\ConditionallyUsesUuids;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * One physically identified unit of a serial-tracked product (D28).
 *
 * ### It is the quantity, rather than carrying one
 *
 * For a serial-tracked product the quantity IS the count of rows here with `released_at IS NULL`
 * (invariant 9). There is no `remaining_quantity` to materialise and no fraction to express, which
 * is why lots and serials are mutually exclusive by nature rather than by policy: half a drill does
 * not exist, and a fungible quantity of four cannot say which four.
 *
 * ### A released unit is kept
 *
 * `released_at` rather than a delete, because a shop asked "did we ever have this serial" needs the
 * answer to be yes rather than silence. That retention is also what makes the `serial -> lot`
 * transition permanently closed: the rows never go away, so the direction never reopens
 * ([Product::booted]).
 */
final class ProductSerial extends Model
{
    use BelongsToTeam;
    use ConditionallyUsesUuids;

    /** @var list<string> */
    protected $fillable = [
        'product_id',
        'location_id',
        'serial',
        'warranty_ends_at',
        'unit_cost',
        'currency',
        'acquired_at',
        'released_at',
    ];

    protected function casts(): array
    {
        return [
            'warranty_ends_at' => 'date',
            'unit_cost' => 'decimal:4',
            'acquired_at' => 'datetime',
            'released_at' => 'datetime',
        ];
    }

    public function product(): BelongsTo
    {
        return $this->belongsTo(Product::class);
    }

    /**
     * Where the unit is. Null once it has left, which is why the column is nullable rather than
     * pointing at a "gone" location.
     */
    public function location(): BelongsTo
    {
        return $this->belongsTo(Location::class);
    }

    /**
     * Still on hand: the rows invariant 9 counts.
     */
    public function scopeHeld(Builder $query): Builder
    {
        return $query->whereNull('released_at');
    }
}
