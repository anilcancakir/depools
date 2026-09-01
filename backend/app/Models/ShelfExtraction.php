<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTeam;
use FlutterSdk\MagicStarter\Support\ConditionallyUsesUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * One attempt at reading a shelf, with the payload the model actually returned.
 *
 * The migration carries why this table exists here and deliberately does not on the single-product
 * path: that model chain was measured on real product photographs, and no equivalent measurement
 * exists for a shelf. `regions_found` beside `raw_payload` is what makes the twelve-region cap
 * revisitable with data.
 */
final class ShelfExtraction extends Model
{
    use BelongsToTeam;
    use ConditionallyUsesUuids;

    /**
     * Matches `shelf_extractions_outcome_is_known`.
     *
     * The five `AiOutcome` cases plus `unreadable`, which is the path with no model in it: a file
     * that will not decode. Same set as `ReceiptExtraction::OUTCOMES`.
     */
    public const OUTCOMES = [
        'succeeded',
        'schema_invalid',
        'provider_error',
        'refused',
        'no_credit',
        'unreadable',
    ];

    /**
     * `created_at` is a database default and there is no `updated_at`: an attempt is written once and
     * never updated, exactly like `ReceiptExtraction` and `AiUsageEvent`.
     */
    public $timestamps = false;

    /** @var list<string> */
    protected $fillable = [
        'shelf_read_id',
        'attempt',
        'provider',
        'model',
        'raw_payload',
        'outcome',
        'error_message',
        'regions_found',
        'duration_ms',
    ];

    /**
     * @return array<string, string>
     */
    protected function casts(): array
    {
        return [
            'attempt' => 'integer',
            'raw_payload' => 'array',
            'regions_found' => 'integer',
            'duration_ms' => 'integer',
            'created_at' => 'datetime',
        ];
    }

    public function shelfRead(): BelongsTo
    {
        return $this->belongsTo(ShelfRead::class);
    }
}
