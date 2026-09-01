<?php

namespace App\Ai;

use App\Enums\AiOutcome;

/**
 * What one attempt in a gateway chain did, reported to whoever asked for the action.
 *
 * **D95 is why this leaves the AI layer at all.** `receipt_extractions` is one row per attempt and
 * the decision says plainly that the table IS O2's bake-off data: choosing the vision model from
 * production evidence rather than from a one-off spreadsheet requires the evidence to be recorded as
 * it happens, and "the first model failed schema validation and the second passed" is exactly the
 * fact that a single column, or a single return value, loses.
 *
 * [GatewayRunner] already knew all of this and kept it to itself: `validate` sees only the structured
 * answer, and the caller sees only whatever survived validation. So the runner takes an optional
 * observer and reports each attempt beside the `ai_usage_events` row it already writes.
 *
 * ### It carries the RAW payload, not the validated result
 *
 * A rejected answer has no validated result, and a rejected answer is the most interesting row the
 * bake-off will read. Null when nothing came back at all: a declined action, a provider that fell
 * over.
 *
 * ### It is a report, not a hook
 *
 * The runner's behaviour does not depend on it and it cannot change the outcome. A throw from an
 * observer is the observer's bug and propagates, rather than being swallowed into a `provider_error`
 * that blames a model that answered correctly.
 */
final readonly class GatewayAttempt
{
    /**
     * @param  int  $attempt  1-based ordinal within this action's chain
     * @param  array<string, mixed>|null  $payload  what the model returned, before validation
     *
     * There is no line count here on purpose. It would be the one field the runner cannot fill,
     * since it has no idea what the answers to any category look like, and the caller can read it
     * off [$payload] where it is already recorded verbatim.
     */
    public function __construct(
        public int $attempt,
        public AiOutcome $outcome,
        public ?string $provider = null,
        public ?string $model = null,
        public ?array $payload = null,
        public ?int $durationMs = null,
        public ?string $errorMessage = null,
    ) {}
}
