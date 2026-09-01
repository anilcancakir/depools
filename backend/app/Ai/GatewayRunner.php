<?php

namespace App\Ai;

use App\Ai\Contracts\ModelCaller;
use App\Enums\AiOutcome;
use App\Models\Scopes\TeamScope;
use Closure;
use Illuminate\Contracts\JsonSchema\JsonSchema;
use Illuminate\Support\Str;
use Throwable;

/**
 * The chokepoint every gateway implementation runs its call through.
 *
 * `ai-design.md` requires four things of every model call and says the interface is the only path,
 * so they live here rather than in each gateway: redaction before anything leaves, a credit check
 * before the call rather than after, a usage row per attempt, and validation of the structured
 * response before it is returned. A gateway that wrote its own loop would eventually forget one, and
 * the MVP's icon endpoint forgetting exactly this is the reason the rule exists.
 *
 * ### Two layers of fallback, because two different things fail (D77)
 *
 * A chain entry is `(provider, [models])`. Inside one entry OpenRouter resolves infrastructure
 * failures itself, within a single HTTP call. Across entries this loop resolves what OpenRouter
 * cannot see: a 200 whose JSON our schema rejects is a successful request to it. Crossing an entry
 * also crosses a provider boundary, which its array cannot do.
 *
 * ### A schema failure asks the NEXT entry more strictly
 *
 * `ai-design.md` asks for a stricter retry after a malformed response, and this is where it fits: the
 * next entry is asked with a suffix naming the failure. It is not a third mechanism, it is what the
 * second entry is FOR.
 *
 * **The suffix applies to every attempt that follows a schema failure, not to one of them.** This
 * said "once" and the code has never done that: `$lastFailedSchema` is a flag about the PREVIOUS
 * attempt, so with three entries and two schema failures the third is asked strictly too. That is
 * the behaviour worth having, since there is no argument for asking a third model less carefully
 * than the second, and capping it would discard a provider-fallback attempt for a schema reason.
 * Unreachable today either way, because every configured chain has two entries.
 *
 * What IS once per action is the total: the chain length bounds the attempts, so a malformed
 * response cannot loop, which is the property `ai-design.md` is protecting when it says "once, then
 * fall back to the manual path".
 */
final class GatewayRunner
{
    /**
     * Appended to the instructions after a response failed our schema.
     *
     * Deliberately about SHAPE rather than about content. A model that produced an unusable card is
     * not helped by being told to try harder; it is helped by being told what the envelope must be.
     */
    private const STRICTER = "\n\nYour previous answer did not match the required schema. Reply with "
        .'JSON matching it exactly: no prose, no code fence, no extra keys, and null rather than an '
        .'empty string for a field you cannot fill.';

    public function __construct(
        private readonly ModelCaller $caller,
        private readonly CreditLedger $credits,
        private readonly UsageRecorder $usage,
        private readonly Redactor $redactor,
    ) {}

    /**
     * Runs one category's chain and returns whatever `$validate` made of the first usable answer.
     *
     * @template T
     *
     * @param  string  $category  a key under `ai_gateways.categories`
     * @param  Closure(JsonSchema): array<string, mixed>  $schema
     * @param  Closure(array<string, mixed>): (T|null)  $validate  null rejects the answer and moves on
     * @param  ImageInput|null  $image  sent with every attempt in the chain, unredacted; see below
     * @param  Closure(GatewayAttempt): void|null  $onAttempt  told about each attempt as it lands
     * @return T|null
     *
     * ### Why an observer exists at all
     *
     * Everything this method learns per attempt (which provider answered, which model, what came
     * back before validation, how long it took) it used to keep: `validate` sees only the structured
     * answer and the caller only what survived. D95 needs it out here, because `receipt_extractions`
     * is one row per attempt and that table IS O2's bake-off data, so "the first model failed schema
     * validation and the second passed" has to be recordable by whoever asked for the action.
     *
     * It is a REPORT. Nothing here branches on it and it cannot change an outcome, so a gateway that
     * passes none behaves exactly as before.
     */
    public function run(
        string $category,
        string $instructions,
        string $input,
        Closure $schema,
        Closure $validate,
        int $credits = 1,
        ?ImageInput $image = null,
        ?Closure $onAttempt = null,
    ): mixed {
        if (! config('ai_gateways.live', true)) {
            return null;
        }

        /** @var array<string, mixed> $config */
        $config = config("ai_gateways.categories.{$category}");

        // `?? []` rather than a bare index: a category configured with a timeout and no chain is a
        // plausible half-edit, and reading the missing key would warn twice and then `foreach` over
        // null. Fail closed and silent is the behaviour this method promises everywhere else.
        $chain = is_array($config) ? ($config['chain'] ?? []) : [];

        if ($chain === []) {
            return null;
        }

        // **No tenant, no call, and no row either.** `TeamScope` fails closed, so with no auth
        // context the balance reads zero and this would take the no-credit path below and try to
        // write an attempt row whose `team_id` is null: the column refuses it and a path that
        // promises null throws SQLSTATE 23502 instead. A queued job or a console command is exactly
        // the caller that arrives here without a request.
        //
        // Nothing is recorded rather than something being recorded anonymously, because the row
        // exists to say WHICH tenant is hitting their limit and a row with no tenant answers nobody.
        if (TeamScope::currentTeamId() === null) {
            return null;
        }

        // Groups this action's attempts. Generated here rather than by the database, because the
        // rows are written one at a time and they have to agree on it before the first is written.
        $actionId = (string) Str::orderedUuid();

        if (! $this->credits->canAfford($credits)) {
            // Recorded even though nothing left the process. "This tenant is hitting their limit" is
            // the most actionable usage fact there is, and it is invisible if a declined action
            // leaves no row at all.
            $this->usage->attempt($actionId, 1, $category, AiOutcome::NoCredit);
            $this->report($onAttempt, new GatewayAttempt(1, AiOutcome::NoCredit));

            return null;
        }

        // **Before the loop, so no retry path can reach a provider with unmasked content.** Doing it
        // per attempt would be the same work three times and one `continue` away from being skipped.
        //
        // **The IMAGE is not redacted, and that is a stated position rather than an omission.**
        // [Redactor] masks identifiers in TEXT; there is no equivalent for pixels, and the only
        // honest alternatives would be refusing to send images at all or pretending a mask happened.
        // What bounds the exposure instead is what an image path is allowed to be: the user's own
        // document, photographed by them, sent to read what they are holding. `legal-and-privacy.md`
        // covers it as processing rather than as redaction. Any future gateway that would send
        // someone ELSE's image is a different decision and does not inherit this one.
        $redacted = (string) $this->redactor->text($input);

        $attempt = 0;
        $lastFailedSchema = false;

        foreach ($chain as $entry) {
            // **Checked before the attempt is counted, not inside it.** A malformed entry is a
            // configuration mistake rather than a model failure, so it must not consume an attempt
            // ordinal or leave a `provider_error` row implying a provider was reached. The `catch`
            // below reads `$entry` too, which is what would have turned a half-edited config into a
            // warning raised from inside the error path.
            if (! is_array($entry) || ! is_string($entry['provider'] ?? null) || ! is_array($entry['models'] ?? null)) {
                continue;
            }

            $attempt++;
            $startedAt = (int) (microtime(true) * 1000);

            try {
                $answer = $this->caller->call(
                    instructions: $instructions.($lastFailedSchema ? self::STRICTER : ''),
                    input: $redacted,
                    models: $entry['models'],
                    schema: $schema,
                    provider: $entry['provider'],
                    timeoutMs: (int) ($config['timeout_ms'] ?? 3000),
                    reasoning: $config['reasoning'] ?? false,
                    image: $image,
                );
            } catch (Throwable $e) {
                // A timeout, a 5xx or a transport failure. Not logged as an error the user sees:
                // every gateway degrades to its manual path, and an exception here would make the
                // feature's failure the caller's problem.
                $this->usage->attempt(
                    $actionId, $attempt, $category, AiOutcome::ProviderError,
                    provider: $entry['provider'],
                    model: $entry['models'][0] ?? null,
                    durationMs: (int) (microtime(true) * 1000) - $startedAt,
                );
                $this->report($onAttempt, new GatewayAttempt(
                    $attempt, AiOutcome::ProviderError,
                    provider: $entry['provider'],
                    model: $entry['models'][0] ?? null,
                    durationMs: (int) (microtime(true) * 1000) - $startedAt,
                    errorMessage: $e->getMessage(),
                ));

                $lastFailedSchema = false;

                continue;
            }

            $durationMs = (int) (microtime(true) * 1000) - $startedAt;
            $cost = $this->costMicroUsd($answer);

            if ($answer->refused) {
                // **Moved on from, never retried more strictly.** A moderation filter will decline
                // the same content however the envelope is described, so treating this as a schema
                // failure would spend a second call to be told the same thing. A different model may
                // well answer, which is exactly what the next entry is.
                $this->usage->attempt(
                    $actionId, $attempt, $category, AiOutcome::Refused,
                    provider: $answer->provider, model: $answer->model,
                    inputTokens: $answer->inputTokens, outputTokens: $answer->outputTokens,
                    costMicroUsd: $cost, durationMs: $durationMs,
                );
                $this->report($onAttempt, new GatewayAttempt(
                    $attempt, AiOutcome::Refused,
                    provider: $answer->provider, model: $answer->model,
                    payload: $answer->structured, durationMs: $durationMs,
                ));

                $lastFailedSchema = false;

                continue;
            }

            $validated = $validate($answer->structured);

            if ($validated === null) {
                // A 200 that we cannot use. It cost tokens and it is billed, which is precisely why
                // the row is written with its cost rather than skipped.
                $this->usage->attempt(
                    $actionId, $attempt, $category, AiOutcome::SchemaInvalid,
                    provider: $answer->provider, model: $answer->model,
                    inputTokens: $answer->inputTokens, outputTokens: $answer->outputTokens,
                    costMicroUsd: $cost, durationMs: $durationMs,
                );
                $this->report($onAttempt, new GatewayAttempt(
                    $attempt, AiOutcome::SchemaInvalid,
                    provider: $answer->provider, model: $answer->model,
                    payload: $answer->structured, durationMs: $durationMs,
                ));

                $lastFailedSchema = true;

                continue;
            }

            $this->usage->attempt(
                $actionId, $attempt, $category, AiOutcome::Succeeded,
                provider: $answer->provider, model: $answer->model,
                inputTokens: $answer->inputTokens, outputTokens: $answer->outputTokens,
                costMicroUsd: $cost, durationMs: $durationMs,
            );
            $this->report($onAttempt, new GatewayAttempt(
                $attempt, AiOutcome::Succeeded,
                provider: $answer->provider, model: $answer->model,
                payload: $answer->structured, durationMs: $durationMs,
            ));

            // Only now. A failed action spends no credit, which `ai-enrichment.md` promises and puts
            // on screen, so charging up front and refunding would be visible and wrong.
            $this->usage->charge($actionId, $credits);

            return $validated;
        }

        return null;
    }

    /**
     * Hands one attempt to the observer, when there is one.
     *
     * **Deliberately not guarded with a try.** An observer that throws is the CALLER's bug, and
     * swallowing it here would turn it into a silent `provider_error` blaming a model that answered
     * correctly, which is the exact shape of failure this class documents elsewhere and exists to
     * avoid. It propagates, and the gateway that installed the observer sees its own stack.
     */
    private function report(?Closure $onAttempt, GatewayAttempt $attempt): void
    {
        if ($onAttempt !== null) {
            $onAttempt($attempt);
        }
    }

    /**
     * Micro-USD for one answer, or null when we do not know the model's price.
     *
     * Integer arithmetic end to end (D84's spirit: PHP computes, and a float summed over a million
     * rows drifts). Rates are micro-USD per million tokens, so the `+ 500_000` is a round-half-up
     * before the divide rather than a truncation that would systematically under-report cost.
     *
     * Null rather than zero for an unpriced model, because a zero reads as "this call was free" in
     * the very report `monetization.md` needs, and a model can be added to a chain without its price.
     */
    private function costMicroUsd(ModelAnswer $answer): ?int
    {
        // **The whole table, then a direct index.** `config('ai_gateways.pricing.'.$model)` reads as
        // the obvious thing and is wrong: a model identifier contains DOTS, which is `config()`'s
        // path separator, so `nvidia/nemotron-3.5-lightning` becomes a walk through `nemotron-3` and
        // then `5-lightning` and finds nothing. It fails silently as a null cost, and it survived a
        // unit test because the model that test names, `deepseek-v4-flash-0731`, happens to have no
        // dot in it. A live call against the configured primary is what surfaced it.
        /** @var array<string, array{input: int, output: int}> $table */
        $table = config('ai_gateways.pricing', []);
        $rates = $table[$answer->model] ?? null;

        if (! is_array($rates)) {
            return null;
        }

        return intdiv($answer->inputTokens * $rates['input'] + 500_000, 1_000_000)
            + intdiv($answer->outputTokens * $rates['output'] + 500_000, 1_000_000);
    }
}
