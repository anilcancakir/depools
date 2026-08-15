<?php

namespace App\Models;

use App\Enums\ActorType;
use App\Enums\MovementReason;
use App\Enums\MovementSource;
use App\Models\Concerns\BelongsToTeam;
use App\Models\Scopes\TeamScope;
use FlutterSdk\MagicStarter\Support\ConditionallyUsesUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\MorphTo;
use RuntimeException;

/**
 * One immutable row in the ledger.
 *
 * ### Append-only is enforced here, and the reason it is not a database trigger
 *
 * Invariant 4 says these rows are never updated or deleted. A trigger would be stronger and D84 rules
 * one out: PostgreSQL stores, indexes and constrains, and it does not compute. The reason recorded
 * here used to be portability, "the suite is sqlite, production is not", which stopped being true
 * when D72 moved the suite onto PostgreSQL. So the model throws, a test asserts that it throws, and
 * the referential half (`restrictOnDelete` on product, location and lot) is in the migration, which
 * together is what the doc asks for.
 *
 * A mistake is corrected by APPENDING a compensating movement with `reason = correction`. That is
 * not a workaround for the missing update; it is the point. The wrong number and its correction are
 * both facts about what happened, and an audit that can only see the final state cannot tell a
 * careful tenant from a careless one.
 *
 * ### `occurred_at` is not `created_at`
 *
 * A receipt entered on Tuesday for a Sunday shop has to age from Sunday, or every forecast built on
 * it is two days optimistic.
 */
final class StockMovement extends Model
{
    use BelongsToTeam;
    use ConditionallyUsesUuids;
    use HasFactory;

    /** The ledger records when a row was written and never when it changed, because it cannot. */
    public const UPDATED_AT = null;

    /** @var list<string> */
    protected $fillable = [
        'product_id',
        'location_id',
        'stock_lot_id',
        'delta',
        // What the user actually typed, beside the base-unit `delta` (D90). Without these a delivery
        // keyed as "2 koli" reads back as "24 adet" on all three surfaces `MovementRow` renders on.
        'entered_quantity',
        'entered_unit',
        'reason',
        'source',
        'actor_type',
        'actor_id',
        'note',
        'idempotency_key',
        'occurred_at',
    ];

    protected function casts(): array
    {
        return [
            'delta' => 'decimal:3',
            'entered_quantity' => 'decimal:3',
            'reason' => MovementReason::class,
            'source' => MovementSource::class,
            'actor_type' => ActorType::class,
            'occurred_at' => 'datetime',
        ];
    }

    /**
     * Refuse every update and every delete, and keep the lot's total true after every insert.
     */
    protected static function booted(): void
    {
        self::updating(static function (): void {
            throw new RuntimeException(
                'stock_movements is append-only. Correct a mistake by writing a compensating '
                .'movement with reason `correction` instead of editing this row.',
            );
        });

        self::deleting(static function (): void {
            throw new RuntimeException(
                'stock_movements is append-only. A movement that should not have happened is '
                .'reversed by a compensating movement, not removed.',
            );
        });

        // The lot's materialised total is refreshed from the ledger rather than incremented, so a
        // double-fired event or a retried job converges instead of drifting.
        //
        // The relation is loaded scope-free deliberately. `TeamScope` would resolve `lot` to null in
        // any context without an authenticated user, so a movement written by a queue worker or a
        // seeder would leave its lot's total stale and report success. That is the exact drift D81
        // holds this application responsible for, arriving through the hook meant to prevent it.
        self::created(static function (self $movement): void {
            $movement->lot()->withoutGlobalScope(TeamScope::class)->first()?->recalculateFromLedger();
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

    public function lot(): BelongsTo
    {
        return $this->belongsTo(StockLot::class, 'stock_lot_id');
    }

    /**
     * The person who did this, when a person did.
     *
     * **Null is the ordinary answer rather than a broken row.** `actor_type` is one of four
     * (`user`, `assistant`, `mcp_client`, `system`) and only the first names a `users` row, so a
     * movement the assistant wrote resolves to null here and the client says "Assistant" from the
     * TYPE instead. Guarding on the type inside the relation would make it uneager-loadable, which
     * is the opposite of what an activity feed needs.
     */
    public function actor(): BelongsTo
    {
        return $this->belongsTo(User::class, 'actor_id');
    }

    /**
     * The receipt, invoice or shopping list that caused this movement, if any.
     */
    public function reference(): MorphTo
    {
        return $this->morphTo();
    }
}
