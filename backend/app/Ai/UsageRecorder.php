<?php

namespace App\Ai;

use App\Enums\AiOutcome;
use App\Models\AiUsageEvent;
use Illuminate\Support\Facades\Auth;

/**
 * Writes the attempt rows, and charges the action once it has succeeded.
 *
 * Split into two calls on purpose. An attempt row is written AS IT HAPPENS, so a process that dies
 * mid-action still leaves evidence of what it spent; the charge lands afterwards, because
 * `ai-enrichment.md` promises a failed read costs no credit and says so on screen. The alternative,
 * buffering the rows until the outcome is known, loses exactly the rows that matter most.
 */
final class UsageRecorder
{
    public function attempt(
        string $actionId,
        int $attempt,
        string $gateway,
        AiOutcome $outcome,
        ?string $provider = null,
        ?string $model = null,
        ?int $inputTokens = null,
        ?int $outputTokens = null,
        ?int $costMicroUsd = null,
        ?int $durationMs = null,
    ): AiUsageEvent {
        return AiUsageEvent::create([
            // `team_id` is stamped by `BelongsToTeam` from the auth context and is not accepted here,
            // which is the same rule every other table follows and the reason no caller can name one.
            'actor_id' => Auth::id(),
            'action_id' => $actionId,
            'attempt' => $attempt,
            'gateway' => $gateway,
            'provider' => $provider,
            'model' => $model,
            'input_tokens' => $inputTokens,
            'output_tokens' => $outputTokens,
            'cost_micro_usd' => $costMicroUsd,
            'duration_ms' => $durationMs,
            'outcome' => $outcome->value,
            // Always zero here. The charge is a separate act below, so an attempt row can never
            // accidentally bill a run that went on to fail.
            'credits_charged' => 0,
        ]);
    }

    /**
     * Bills a succeeded action, on its first attempt.
     *
     * The first specifically, because a CHECK constraint refuses a charge on any other, which keeps
     * the balance a plain sum over the whole table rather than one that has to group attempts back
     * into actions first.
     */
    public function charge(string $actionId, int $credits): void
    {
        if ($credits < 1) {
            return;
        }

        AiUsageEvent::query()
            ->where('action_id', $actionId)
            ->where('attempt', 1)
            ->update(['credits_charged' => $credits]);
    }
}
