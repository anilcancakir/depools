<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTeam;
use FlutterSdk\MagicStarter\Support\ConditionallyUsesUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * One extraction ATTEMPT over a receipt, with the payload the model actually returned.
 *
 * Same shape as `AiUsageEvent` for the same reason (D78): the attempt is the row, and the migration
 * carries why a jsonb column on `receipts` would have lost the retry the bake-off needs.
 */
final class ReceiptExtraction extends Model
{
    use BelongsToTeam;
    use ConditionallyUsesUuids;

    /**
     * Matches `receipt_extractions_outcome_is_known`.
     *
     * The five `AiOutcome` cases, because both this table and `ai_usage_events` describe the same
     * attempt, plus `unreadable` for the path with no model in it: a deterministic XML parse that
     * met a document it could not read.
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
     * `created_at` is a database default (`useCurrent()`) and there is no `updated_at` column: an
     * attempt is written once and never updated, exactly like `AiUsageEvent`.
     */
    public $timestamps = false;

    /** @var list<string> */
    protected $fillable = [
        'receipt_id',
        'attempt',
        'provider',
        'model',
        'raw_payload',
        'outcome',
        'error_message',
        'lines_found',
        'duration_ms',
    ];

    protected function casts(): array
    {
        return [
            'attempt' => 'integer',
            'raw_payload' => 'array',
            'lines_found' => 'integer',
            'duration_ms' => 'integer',
            'created_at' => 'datetime',
        ];
    }

    public function receipt(): BelongsTo
    {
        return $this->belongsTo(Receipt::class);
    }
}
