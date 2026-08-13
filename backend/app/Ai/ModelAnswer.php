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
     */
    public function __construct(
        public array $structured,
        public ?string $provider,
        public ?string $model,
        public int $inputTokens,
        public int $outputTokens,
    ) {}
}
