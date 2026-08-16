<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTeam;
use App\Services\ShoppingListGenerator;
use FlutterSdk\MagicStarter\Support\ConditionallyUsesUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * One line of the shopping list: what to buy, how much, and why.
 *
 * Three kinds of row share this table and the differences are the design. A GENERATED row is rebuilt
 * by the generator when its output goes stale; a TICKED row is the user saying the thing is in the
 * trolley (D47); a MANUAL row is something they typed, which may not be in the catalogue at all
 * (D100). Only the first is replaceable.
 *
 * **The reason is a code plus frozen inputs, never a sentence** (D98). The migration carries the
 * argument; the consequence here is that nothing on this model renders anything.
 *
 * @see ShoppingListGenerator
 */
final class ShoppingListItem extends Model
{
    use BelongsToTeam;
    use ConditionallyUsesUuids;

    /**
     * Why a line is on the list, which is also what SHAPE of sentence it may become (D46).
     *
     * Closed by a CHECK, and a second CHECK enforces the gate that matters: only `running_out` and
     * `expiring` may carry a day count, so two to nine movements earns a bucket and never a number
     * at any precision.
     */
    public const REASONS = ['running_out', 'roughly_due', 'below_target', 'expiring', 'manual'];

    /** @var list<string> */
    protected $fillable = [
        'team_id',
        'shopping_list_id',
        'product_id',
        'name',
        'quantity',
        'unit',
        'reason',
        'reason_days',
        'reason_bucket',
        'reason_on_hand',
        'reason_lot_is_open',
        'reason_target',
        'reason_movement_count',
        'checked_at',
    ];

    protected function casts(): array
    {
        return [
            'quantity' => 'decimal:3',
            'reason_days' => 'integer',
            'reason_on_hand' => 'decimal:3',
            'reason_lot_is_open' => 'boolean',
            'reason_target' => 'decimal:3',
            'reason_movement_count' => 'integer',
            'checked_at' => 'datetime',
        ];
    }

    public function product(): BelongsTo
    {
        return $this->belongsTo(Product::class);
    }

    public function list(): BelongsTo
    {
        return $this->belongsTo(ShoppingList::class, 'shopping_list_id');
    }

    /** Whether the thing is in the trolley. Not stock (D47). */
    public function isChecked(): bool
    {
        return $this->checked_at !== null;
    }

    /**
     * Whether the generator may replace this row.
     *
     * **A tick freezes the line it is on**, and that is the load-bearing half. Buying the milk is
     * exactly what stops the milk being short, so a regeneration that dropped every line the ledger
     * no longer justified would erase each item from the trolley as the user recorded picking it up.
     *
     * A manual line is never touched either: the user typed it, so nothing gets to decide on their
     * behalf that they no longer want it.
     */
    public function isReplaceable(): bool
    {
        return $this->reason !== 'manual' && ! $this->isChecked();
    }
}
