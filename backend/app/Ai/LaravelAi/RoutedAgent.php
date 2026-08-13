<?php

namespace App\Ai\LaravelAi;

use Closure;
use Illuminate\Contracts\JsonSchema\JsonSchema;
use Laravel\Ai\AnonymousAgent;
use Laravel\Ai\Contracts\HasProviderOptions;
use Laravel\Ai\Contracts\HasStructuredOutput;
use Laravel\Ai\Enums\Lab;

/**
 * A structured agent that carries OpenRouter's own fallback array into the request body.
 *
 * **A named class rather than `laravel/ai`'s `agent()` helper, for two reasons that both bite.**
 *
 * The first is the feature this exists for. `TextGenerationOptions::providerOptions()` reads options
 * off the agent only when it `instanceof HasProviderOptions`, and the anonymous agents the helper
 * builds implement `Agent`, `Conversational`, `HasTools` and (structured) `HasStructuredOutput`, but
 * never that one. So an anonymous agent cannot send `models`, and D77's infrastructure layer, the
 * fallback OpenRouter resolves inside a single HTTP call, would be unreachable.
 *
 * The second is testing. `Ai::fakeAgent()` is keyed on a CLASS NAME, so faking an anonymous agent
 * means faking `StructuredAnonymousAgent` and therefore every anonymous agent in the process at once.
 * A named class is a seam a test can aim at.
 *
 * The class is generic rather than one subclass per task because the routing is the same mechanism
 * everywhere and only the instructions, the schema and the chain differ. Those are constructor
 * arguments, which keeps the count of these at one.
 */
final class RoutedAgent extends AnonymousAgent implements HasProviderOptions, HasStructuredOutput
{
    /**
     * @param  list<string>  $models  ordered; the first is asked, the rest are OpenRouter's fallbacks
     * @param  Closure(JsonSchema): array<string, mixed>  $schemaFactory
     * @param  bool|string  $reasoning  false disables it; a string is an effort level
     */
    public function __construct(
        public string $instructions,
        private readonly array $models,
        private readonly Closure $schemaFactory,
        private readonly bool|string $reasoning = false,
    ) {
        parent::__construct($instructions, [], []);
    }

    public function schema(JsonSchema $schema): array
    {
        return ($this->schemaFactory)($schema);
    }

    /**
     * Extra body keys for the provider, merged into the request by the OpenRouter gateway.
     *
     * Only OpenRouter gets them: `models` and `reasoning` are its own routing vocabulary, and another
     * provider receiving them would either error or, worse, ignore them silently and leave a chain we
     * believe is configured doing nothing.
     *
     * **`reasoning` is set explicitly and always**, because several models here reason by default at
     * high effort. Measured on this repository's own translation task, `deepseek-v4-flash-0731` took
     * 34 seconds and 5x the tokens with its default on, and 2.6 seconds with it off. Leaving the key
     * absent means inheriting whatever each model decided, which is not a configuration.
     *
     * @return array<string, mixed>
     */
    public function providerOptions(Lab|string $provider): array
    {
        $name = $provider instanceof Lab ? $provider->value : $provider;

        if ($name !== 'openrouter') {
            return [];
        }

        return [
            // The first model is already sent as `model`; the array is what OpenRouter falls back
            // THROUGH on a context-length rejection, a moderation flag, a rate limit or downtime.
            'models' => $this->models,
            'reasoning' => is_string($this->reasoning)
                ? ['effort' => $this->reasoning]
                : ['enabled' => $this->reasoning],
        ];
    }
}
