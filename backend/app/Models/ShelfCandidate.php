<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTeam;
use FlutterSdk\MagicStarter\Support\ConditionallyUsesUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * One region a shelf photograph produced: where it sits, what it was read as, and what it resolved to.
 *
 * The migration carries why the box is fractions, why the region number is load-bearing (D60) and why
 * `created` is the one resolution allowed to point at nothing yet. Nothing here duplicates a CHECK;
 * the `const` arrays exist for a validator to reference.
 */
final class ShelfCandidate extends Model
{
    use BelongsToTeam;
    use ConditionallyUsesUuids;

    /**
     * `unresolved`, `matched`, `created`, `rejected`. Matches `shelf_candidates_resolution_is_known`.
     *
     * The same four `ReceiptLine::RESOLUTIONS` carries, on purpose: the client draws both through one
     * `LineResolution`, because an extracted thing resolving to a product is the same concept
     * whichever picture it came out of.
     */
    public const RESOLUTIONS = ['unresolved', 'matched', 'created', 'rejected'];

    /**
     * Which step answered. Matches `shelf_candidates_resolved_by_is_known`.
     *
     * The receipt's spellings for the three steps this path can reach. It allows seven; a shelf name
     * is answered by the alias table, by the tenant's own products, or by the user at commit.
     */
    public const RESOLVED_BY = ['alias', 'own_product', 'manual'];

    /** @var list<string> */
    protected $fillable = [
        'shelf_read_id',
        'region',
        'box_left',
        'box_top',
        'box_width',
        'box_height',
        'raw_name',
        'raw_name_normalized',
        'quantity',
        'raw_unit_code',
        'resolved_unit',
        'confidence',
        'resolution',
        'product_id',
        'global_product_id',
        'resolved_by',
    ];

    /**
     * @return array<string, string>
     */
    protected function casts(): array
    {
        return [
            'region' => 'integer',
            // Cast to float rather than left as the decimal string PostgreSQL sends, because these
            // are multiplied by a widget's width on the way to a screen and a string would arrive
            // there as a silent zero.
            'box_left' => 'float',
            'box_top' => 'float',
            'box_width' => 'float',
            'box_height' => 'float',
            // **NOT cast to float**, and that is the same call `receipt_lines` makes: a quantity
            // reaches the ledger, so it travels as the string PostgreSQL sends and the decimal
            // survives the trip.
            'confidence' => 'integer',
        ];
    }

    /**
     * Whether this candidate would be written as it stands.
     *
     * Mirrors the client's own `ShelfCandidate.isSettled`. D60 makes this the number the accept
     * button carries: six regions yielded four products in the fixture, and a button labelled six
     * would promise to write an unnamed bottle and a price label the recogniser mistook for stock.
     */
    public function isSettled(): bool
    {
        return in_array($this->resolution, ['matched', 'created'], true);
    }

    public function shelfRead(): BelongsTo
    {
        return $this->belongsTo(ShelfRead::class);
    }

    public function product(): BelongsTo
    {
        return $this->belongsTo(Product::class);
    }
}
