<?php

namespace App\Ai\Contracts;

use App\Ai\ModelAnswer;
use Closure;
use Illuminate\Contracts\JsonSchema\JsonSchema;

/**
 * One structured model call, with everything policy-shaped already decided by the caller.
 *
 * **The seam that keeps `laravel/ai` at arm's length.** D6 pins that package to an exact version
 * because it is a v0.x on a monthly minor cadence whose minors can break, and the whole argument for
 * the gateway interfaces is that a break should touch implementation classes rather than the
 * codebase. This is the narrowest point that argument can be made at: one method, no package types in
 * its signature except the schema builder, and one implementation behind it.
 *
 * It is also what lets [\App\Ai\GatewayRunner] be tested for what it actually guards, the credit
 * check, the attempt rows, the chain order and the schema retry, without an HTTP call in sight.
 * Faking at the `Ai` facade instead would test the package's fake rather than our accounting.
 */
interface ModelCaller
{
    /**
     * Calls one entry of a chain and returns whatever came back.
     *
     * **Throws on any transport failure** rather than returning null, because the runner has to tell
     * a provider that fell over from a provider that answered with something unusable: those are two
     * different `ai_usage_events` outcomes and two different operational stories.
     *
     * @param  list<string>  $models  ordered; the first is asked, the rest are the provider's own fallbacks
     * @param  Closure(JsonSchema): array<string, mixed>  $schema
     * @param  bool|string  $reasoning  false disables it; a string is an effort level
     *
     * @throws \Throwable
     */
    public function call(
        string $instructions,
        string $input,
        array $models,
        Closure $schema,
        string $provider,
        int $timeoutMs,
        bool|string $reasoning,
    ): ModelAnswer;
}
