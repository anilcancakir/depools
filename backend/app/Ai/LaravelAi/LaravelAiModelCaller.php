<?php

namespace App\Ai\LaravelAi;

use App\Ai\Contracts\ModelCaller;
use App\Ai\ImageInput;
use App\Ai\ModelAnswer;
use Closure;
use Laravel\Ai\Files\Base64Image;
// **`Responses\Data`, not `Enums`, and the difference was a total outage.** The pinned v0.10.3
// carries this enum here; `Laravel\Ai\Enums\FinishReason` does not exist in it. The import
// therefore raised a class-not-found on the line that maps a SUCCESSFUL response, after the HTTP
// call had been made and billed. `GatewayRunner` catches `Throwable`, records `provider_error` and
// moves on, so every model call in the application returned null through both chain entries and
// nothing anywhere said why. Measured against a live provider: 12 names, 12 nulls, roughly 700ms
// each, which is the shape of two real round trips rather than a config problem.
//
// Nothing in the suite could see it, and that is structural rather than an oversight: every AI test
// binds a fake `ModelCaller`, and this class is the one thing the fake replaces. So the check is
// `bin/check`-visible instead, as an assertion that the class exists.
use Laravel\Ai\Responses\Data\FinishReason;
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
        ?ImageInput $image = null,
    ): ModelAnswer {
        if ($models === []) {
            throw new RuntimeException('A chain entry has no models.');
        }

        $response = (new RoutedAgent($instructions, $models, $schema, $reasoning))
            ->prompt(
                $input,
                // **An attachment, not a data url pasted into the text.** A model reads an image
                // part; a data url inside the prompt is a very long string it reads as characters,
                // which costs the tokens and answers nothing. This is also the boundary D6 cares
                // about: `Base64Image` is named here and nowhere else, so a break in the package's
                // file types touches this line rather than every gateway.
                attachments: $image === null
                    ? []
                    : [new Base64Image($image->base64, $image->mimeType)],
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
