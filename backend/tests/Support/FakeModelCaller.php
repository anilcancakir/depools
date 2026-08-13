<?php

namespace Tests\Support;

use App\Ai\Contracts\ModelCaller;
use App\Ai\ModelAnswer;
use Closure;
use RuntimeException;

/**
 * A scripted [ModelCaller], so the runner's accounting can be tested without a provider.
 *
 * Faking at `laravel/ai`'s own `Ai::fakeAgent()` would test that package's fake. What needs testing
 * here is ours: that a declined action leaves a row, that a schema failure moves to the next entry
 * with a stricter instruction, that the charge lands on attempt 1 and only after success, and that
 * the model recorded is the one that ANSWERED.
 */
final class FakeModelCaller implements ModelCaller
{
    /** @var list<array{instructions: string, input: string, models: list<string>, provider: string, timeoutMs: int, reasoning: bool|string}> */
    public array $calls = [];

    /** @var list<array<string, mixed>|RuntimeException> */
    private array $script;

    /**
     * @param  list<array<string, mixed>|RuntimeException>  $script  one entry per expected call; an
     *                                                               exception entry is thrown instead
     */
    public function __construct(array $script, private readonly ?string $answeringModel = null)
    {
        $this->script = $script;
    }

    public function call(
        string $instructions,
        string $input,
        array $models,
        Closure $schema,
        string $provider,
        int $timeoutMs,
        bool|string $reasoning,
    ): ModelAnswer {
        $this->calls[] = compact('instructions', 'input', 'models', 'provider', 'timeoutMs', 'reasoning');

        $next = array_shift($this->script);

        if ($next === null) {
            throw new RuntimeException('FakeModelCaller ran out of scripted answers.');
        }

        if ($next instanceof RuntimeException) {
            throw $next;
        }

        // A scripted refusal, which a provider reports as a 200 carrying nothing rather than as an
        // error. Spelled as a key in the answer so a test reads like the wire does.
        $refused = ($next['__refused'] ?? false) === true;
        unset($next['__refused']);

        return new ModelAnswer(
            structured: $next,
            refused: $refused,
            provider: $provider,
            // Defaults to the SECOND model of the entry when one is not named, because that is the
            // case worth exercising: OpenRouter answering from its own fallback array means the
            // model billed is not the model asked for.
            model: $this->answeringModel ?? ($models[1] ?? $models[0]),
            inputTokens: 100,
            outputTokens: 40,
        );
    }
}
