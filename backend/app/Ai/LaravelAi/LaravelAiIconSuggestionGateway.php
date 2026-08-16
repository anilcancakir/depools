<?php

namespace App\Ai\LaravelAi;

use App\Ai\Contracts\IconSuggestionGateway;
use App\Ai\GatewayRunner;
use App\Ai\IconHint;
use Illuminate\Contracts\JsonSchema\JsonSchema;

/**
 * Icon suggestion, over `laravel/ai`.
 *
 * Holds the PROMPT and the SCHEMA and nothing else, the same shape as
 * [LaravelAiProductEnrichmentGateway]: redaction, the credit check, the chain, the attempt rows and
 * the stricter retry all live in [GatewayRunner].
 */
final class LaravelAiIconSuggestionGateway implements IconSuggestionGateway
{
    /**
     * How many words the model may return.
     *
     * Four, because the lookup walks them in order and stops at the first that matches anything: a
     * longer list is not a better answer, it is a longer tail of increasingly generic words that
     * would rescue a bad first guess by finding SOMETHING. Two or three is the usual answer.
     */
    private const MAX_TERMS = 4;

    /**
     * The instructions, which are mostly about what a term is.
     *
     * - **A physical thing, not a category.** Asked plainly, models answer `storage` and `inventory`
     *   for half of all inputs, and those are words this catalogue has thousands of. The icon a user
     *   wants for `Kiler` is a cupboard, not a box.
     * - **Lowercase single words.** `search_text` holds space-separated lowercase text and the query
     *   requires every word to match, so a returned phrase narrows to nothing.
     * - **Confidence is about the NAME, not about the model.** `Raf 3` and `A-12` name a place with
     *   no describable object in them, and the right answer there is the neutral icon rather than a
     *   shelf glyph inferred from a number. Stated with examples because a model asked for a
     *   confidence with no anchor returns 0.9 for everything.
     */
    private const INSTRUCTIONS = <<<'TXT'
        You help an inventory application choose an icon for a storage place the user just named.

        The name arrives in the user's own language, which is often not English.

        Return English search words for the PHYSICAL OBJECT or ROOM the name refers to, best first.

        Rules, in order of importance:
        1. Each term is a single lowercase English noun. Never a phrase, never plural, never a brand.
        2. Name the concrete thing, not the abstract category. For "Kiler" answer "cupboard" and
           "pantry", not "storage" or "inventory". Words like storage, inventory, place, item and
           container are never useful here.
        3. Order the terms from most specific to most general. The first one is the answer; the rest
           are what to try if the catalogue does not have it.
        4. Confidence describes the NAME, not your fluency. A name that clearly refers to a thing
           ("Buzdolabı", "Derin dondurucu", "Garaj") is 0.9 or above. A name that is a code, a
           number, a person's name or a bare label ("Raf 3", "A-12", "Depo 2", "Ayşe") is 0.3 or
           below, even when you can guess: the application shows a neutral icon below the threshold,
           which is the correct answer for a name that describes nothing.
        5. When the name mixes both ("Mutfak dolabı 2"), read the describable part and stay high.
        TXT;

    public function __construct(private readonly GatewayRunner $runner) {}

    public function suggest(string $subject): ?IconHint
    {
        return $this->runner->run(
            // **The same category as translation, deliberately.** Both are short text in, short text
            // out, with a user waiting at a form, which is what `enrichment_text` is tuned for: its
            // models were measured on exactly this latency-weighted shape and its docblock says a
            // model added to a chain without its own bake-off is a measurement of a setting. A new
            // category here would be that, with no measurement behind it.
            category: 'enrichment_text',
            instructions: self::INSTRUCTIONS,
            input: 'Place name: '.$subject,
            schema: static fn (JsonSchema $schema): array => [
                'terms' => $schema->array()->items($schema->string())->required()
                    ->description('English search words for the place, best first, at most '.self::MAX_TERMS.'.'),
                'confidence' => $schema->number()->required()
                    ->description('0 to 1. How clearly the name describes a physical object or room.'),
            ],
            validate: static function (array $structured): ?IconHint {
                $confidence = $structured['confidence'] ?? null;

                // A number is the whole point of the field: an answer without one cannot be
                // thresholded, and a suggestion that cannot be thresholded is the confidently wrong
                // glyph this gateway exists to avoid. So it goes back as a schema failure.
                if (! is_numeric($confidence)) {
                    return null;
                }

                $terms = [];

                foreach (is_array($structured['terms'] ?? null) ? $structured['terms'] : [] as $term) {
                    if (! is_string($term)) {
                        continue;
                    }

                    // Lowercased and collapsed here rather than trusted: rule 1 is the one models
                    // break, and `search_text` is lowercase with single spaces, so a stray capital
                    // or a double space would narrow the LIKE query to nothing.
                    $term = mb_strtolower(trim(preg_replace('/\s+/u', ' ', $term) ?? ''));

                    if ($term !== '' && ! in_array($term, $terms, true)) {
                        $terms[] = $term;
                    }
                }

                // No terms is not a weak answer, it is an unusable one.
                if ($terms === []) {
                    return null;
                }

                return new IconHint(
                    terms: array_slice($terms, 0, self::MAX_TERMS),
                    // Clamped rather than rejected. A model answering 1.4 has still told us it is
                    // sure, and refusing the whole call over the arithmetic would spend a second
                    // attempt to be told the same thing in the same shape.
                    confidence: max(0.0, min(1.0, (float) $confidence)),
                );
            },
        );
    }
}
