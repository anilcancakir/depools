<?php

namespace App\Ai\LaravelAi;

use App\Ai\Contracts\ModelCaller;
use App\Ai\ModelAnswer;
use Closure;
use Laravel\Ai\Enums\FinishReason;
use Laravel\Ai\Responses\StructuredAgentResponse;
use RuntimeException;

/**
 * The one place `laravel/ai` is actually spoken to.
 *
 * Thin on purpose: everything above it is our own policy, and everything this does is translate one
 * call into that package's vocabulary and one response back out of it.
 */
final class LaravelAiModelCaller implements ModelCaller
{
    public function call(
        string $instructions,
        string $input,
        array $models,
        Closure $schema,
        string $provider,
        int $timeoutMs,
        bool|string $reasoning,
    ): ModelAnswer {
        if ($models === []) {
            throw new RuntimeException('A chain entry has no models.');
        }

        $response = (new RoutedAgent($instructions, $models, $schema, $reasoning))
            ->prompt(
                $input,
                provider: $provider,
                // The first of the chain. The rest travel in the body as OpenRouter's own fallback
                // array, which `RoutedAgent::providerOptions()` puts there.
                model: $models[0],
                // **Seconds, and the package offers no finer unit**, so a sub-second budget cannot be
                // expressed. Rounding UP is the only safe direction: rounding 1500ms down to 1s would
                // cut off a call that our own configuration says is allowed to take longer.
                timeout: (int) ceil($timeoutMs / 1000),
            );

        if (! $response instanceof StructuredAgentResponse) {
            // A structured agent that came back unstructured is a contract break rather than a bad
            // answer, so it is not something the schema-retry loop should paper over.
            throw new RuntimeException('Expected a structured response from a structured agent.');
        }

        return new ModelAnswer(
            structured: $response->structured,
            // **A refusal is a 200 with nothing in it**, so without this it would arrive as a schema
            // failure and be retried with a stricter instruction: precisely the wrong response to a
            // moderation filter, which will decline the same content however strictly it is asked.
            // The reason lives on the last STEP rather than on the response, which is why the enum
            // had a `refused` case nothing could ever write.
            refused: $response->steps->last()?->finishReason === FinishReason::ContentFilter,
            // From the response's own meta, never from `$models[0]`: OpenRouter may have served this
            // from the second or third entry and the bill follows whichever answered.
            provider: $response->meta->provider,
            model: $response->meta->model,
            inputTokens: $response->usage->promptTokens,
            outputTokens: $response->usage->completionTokens,
        );
    }
}
