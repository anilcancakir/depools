<?php

namespace App\Ai;

/**
 * What one model attempt came back with, before anyone has judged whether it is usable.
 *
 * `provider` and `model` are what ANSWERED rather than what was asked for. OpenRouter's fallback array
 * can serve a request from the second or third model, its documentation says the request is priced at
 * whichever did, and it returns that name in the response body. Recording the requested model would
 * therefore attribute a bill to a model that never ran.
 */
final readonly class ModelAnswer
{
    /**
     * @param  array<string, mixed>  $structured
     * @param  bool  $refused  the provider declined rather than answered, and the difference is not
     *                         cosmetic: a refusal costs tokens, produces nothing, and a rate of it
     *                         rising means a prompt is tripping a moderation filter rather than an
     *                         outage. Reported as its own outcome so those two never look alike.
     */
    public function __construct(
        public array $structured,
        public ?string $provider,
        public ?string $model,
        public int $inputTokens,
        public int $outputTokens,
        public bool $refused = false,
    ) {}
}
