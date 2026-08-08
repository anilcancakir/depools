<?php

declare(strict_types=1);

namespace App\Models;

use App\Models\Concerns\BelongsToTeam;
use Carbon\CarbonInterface;
use FlutterSdk\MagicStarter\Support\ConditionallyUsesUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * One inbound batch of a product at a location.
 *
 * ### The binding date is not always `expires_at`
 *
 * Once `opened_at` is set the lot must go within `products.opened_shelf_life_days` of that moment,
 * which is usually much sooner than the printed date: a carton with a week left on the box has
 * three days left once opened. Every surface that asks "what expires first" resolves the earlier of
 * the two, and FEFO prefers an open lot over a merely-earlier printed date (D27).
 *
 * ### `remaining_quantity` is materialised, never authored
 *
 * Invariant 2: it equals `initial_quantity` plus the sum of this lot's deltas, and is never
 * negative. [recalculateFromLedger] is the only thing that writes it.
 */
final class StockLot extends Model
{
    use BelongsToTeam;
    use ConditionallyUsesUuids;
    use HasFactory;

    /** @var list<string> */
    protected $fillable = [
        'product_id',
        'location_id',
        'lot_code',
        'expires_at',
        'received_at',
        'unit_cost',
        'currency',
        'initial_quantity',
        'opened_at',
    ];

    protected function casts(): array
    {
        return [
            'expires_at' => 'date',
            'received_at' => 'datetime',
            'opened_at' => 'datetime',
            'closed_at' => 'datetime',
            'initial_quantity' => 'decimal:3',
            'remaining_quantity' => 'decimal:3',
            'unit_cost' => 'decimal:4',
        ];
    }

    /**
     * A new lot starts holding exactly what arrived.
     *
     * Set here rather than left to the caller because `remaining_quantity` is not nullable and a
     * caller that forgets it would fail at the database with a message about a column instead of
     * about a lot.
     */
    protected static function booted(): void
    {
        self::creating(static function (self $lot): void {
            if ($lot->getAttribute('remaining_quantity') === null) {
                $lot->setAttribute('remaining_quantity', $lot->getAttribute('initial_quantity'));
            }
        });
    }

    public function product(): BelongsTo
    {
        return $this->belongsTo(Product::class);
    }

    public function location(): BelongsTo
    {
        return $this->belongsTo(Location::class);
    }

    public function movements(): HasMany
    {
        return $this->hasMany(StockMovement::class);
    }

    /**
     * The date this lot actually has to be used by.
     *
     * The earlier of the printed date and the opened-shelf-life deadline. Null only when the lot
     * has neither, which is the normal case for a non-perishable.
     */
    public function bindingDate(): ?CarbonInterface
    {
        $printed = $this->expires_at;

        $openedDeadline = $this->opened_at !== null && $this->product?->opened_shelf_life_days !== null
            ? $this->opened_at->copy()->addDays($this->product->opened_shelf_life_days)
            : null;

        if ($printed === null) {
            return $openedDeadline;
        }

        if ($openedDeadline === null) {
            return $printed;
        }

        return $openedDeadline->lessThan($printed) ? $openedDeadline : $printed;
    }

    /**
     * Recompute `remaining_quantity` and `closed_at` from this lot's own movements.
     *
     * The ledger is the only source. Called after every write to the ledger, and safe to call at
     * any time, which is what makes the drift check in invariant 2 a comparison rather than a
     * guess: run this and see whether anything changed.
     */
    public function recalculateFromLedger(): void
    {
        $remaining = (float) $this->initial_quantity + (float) $this->movements()->sum('delta');

        // Clamped at zero rather than allowed negative. A ledger that drove a lot below zero is a
        // bug in whatever wrote it, and storing the negative would spread that bug into every
        // total that reads this column. The test asserts the ledger cannot get there.
        $this->forceFill([
            'remaining_quantity' => max($remaining, 0),
            'closed_at' => $remaining <= 0 ? ($this->closed_at ?? now()) : null,
        ])->save();
    }
}
