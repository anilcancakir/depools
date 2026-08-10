<?php

declare(strict_types=1);

namespace App\Models;

use App\Models\Concerns\BelongsToTeam;
use FlutterSdk\MagicStarter\Support\ConditionallyUsesUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * The materialised total for one (product, location) pair.
 *
 * Read-only from the application's point of view: every write goes through
 * [StockLedger::rebuildProductStock]. Nothing here is authored, and a setter on this model would be
 * a way to make the ledger and the totals disagree.
 *
 * ### The trait is not optional, and its absence was invisible on SQLite
 *
 * This model was the one table whose model lacked `ConditionallyUsesUuids` while its migration used
 * `MigrationHelper::primaryKey()`. With integer keys that costs nothing, because the database fills
 * an autoincrement column in. With uuids there is no autoincrement: the trait's `creating` listener
 * IS the id generator, so `updateOrCreate` issued an insert with a null primary key.
 *
 * The general form is worth carrying to every table added from here: **under uuid keys, any write
 * that does not pass through Eloquent's model events has to supply the key itself.** That covers a
 * missing trait, and it also covers `upsert()`, `insert()` and raw statements, none of which fire
 * `creating` at all.
 */
final class ProductStock extends Model
{
    use BelongsToTeam;
    use ConditionallyUsesUuids;

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
