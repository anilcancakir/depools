<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTeam;
use FlutterSdk\MagicStarter\Support\ConditionallyUsesUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * One model ATTEMPT, and the consumption half of the credit balance.
 *
 * The migration carries the reasoning; two consequences show up in code here.
 *
 * **`credits_charged` lives on the first attempt of an action and only there**, enforced by a CHECK
 * constraint, so the balance stays a plain sum rather than one that has to know which attempts belong
 * together. It is written after an action SUCCEEDS: `ai-enrichment.md` promises a failed read spends
 * no credit, and it says so on screen.
 *
 * **`provider` and `model` record what ANSWERED**, read from the response, because OpenRouter's own
 * documentation says a request served through its fallback array is priced at the model that served
 * it and returns that model in the response body.
 */
final class AiUsageEvent extends Model
{
    use BelongsToTeam;
    use ConditionallyUsesUuids;

    /**
     * `created_at` is a database default and there is no `updated_at` column to maintain.
     *
     * **The row is written once and updated exactly once more, by [UsageRecorder::charge].** This
     * comment used to claim it was never modified, which was the tidier sentence and not the true
     * one. The update is deliberate: a charge belongs to an ACTION and lands on its first attempt,
     * and it lands only after the action has succeeded, because `ai-enrichment.md` promises a failed
     * read spends no credit and says so on screen. Writing the charge up front and reversing it would
     * be a refund the user watches happen.
     */
    public $timestamps = false;

    protected $fillable = [
        'actor_id',
        'action_id',
        'attempt',
        'gateway',
        'provider',
        'model',
        'input_tokens',
        'output_tokens',
        'cost_micro_usd',
        'credits_charged',
        'outcome',
        'duration_ms',
    ];

    protected function casts(): array
    {
        return [
            'attempt' => 'integer',
            'input_tokens' => 'integer',
            'output_tokens' => 'integer',
            'cost_micro_usd' => 'integer',
            'credits_charged' => 'integer',
            'duration_ms' => 'integer',
            'created_at' => 'datetime',
        ];
    }
}
