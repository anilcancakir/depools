<?php

namespace App\Ai\LaravelAi;

use App\Ai\Contracts\ProductEnrichmentGateway;
use App\Ai\GatewayRunner;
use App\Ai\ProductCard;
use Illuminate\Contracts\JsonSchema\JsonSchema;

/**
 * Product enrichment, over `laravel/ai`.
 *
 * The class holds the PROMPT and the SCHEMA and nothing else. Redaction, the credit check, the chain,
 * the attempt rows and the retry all live in [GatewayRunner], because those are the same for every
 * gateway and duplicating them per gateway is how one of them eventually drifts.
 */
final class LaravelAiProductEnrichmentGateway implements ProductEnrichmentGateway
{
    /**
     * The instructions, which are mostly a list of things not to do.
     *
     * Every clause below is a failure that was measured on real cards rather than imagined:
     *
     * - **Brands.** `Ülker` came back as `İlker` and `Beypazarı` as `Beypazara` from the cheap tier,
     *   and one model helpfully translated a brand that reads like a common noun. A brand is the
     *   single field a user notices being wrong, so it is stated twice and checked after.
     * - **Quantities.** `40 g` became `160g` once. A pack size the model adjusts is stock that is
     *   wrong by a factor.
     * - **Null rather than invention.** Given a card with no description, models cheerfully wrote
     *   one. `ai-enrichment.md` makes this a rule: uncertainty is null, not a guess.
     */
    private const INSTRUCTIONS = <<<'TXT'
        You translate grocery product cards for an inventory application.

        Translate the name and the description into the target language.

        Rules, in order of importance:
        1. Keep the BRAND verbatim. A brand is a proper noun and is never translated, transliterated
           or re-cased, even when it is spelled like an ordinary word in either language.
        2. Keep every quantity, unit and pack size exactly as given. Never convert, round or restate
           them.
        3. If an input field is null or empty, return null for it. Never invent a detail that is not
           in the input, and never describe a product you are only inferring.
        4. Return only the three fields of the schema.
        TXT;

    public function __construct(private readonly GatewayRunner $runner) {}

    public function translate(ProductCard $card, string $targetLocale): ?ProductCard
    {
        return $this->runner->run(
            category: 'enrichment_text',
            instructions: self::INSTRUCTIONS,
            input: sprintf(
                "Target language: %s\n\n%s",
                $targetLocale,
                (string) json_encode($card->toArray(), JSON_UNESCAPED_UNICODE),
            ),
            schema: static fn (JsonSchema $schema): array => [
                'name' => $schema->string()->min(1)->required()
                    ->description('The product name in the target language.'),
                'brand' => $schema->string()->nullable()
                    ->description('The brand, copied verbatim from the input.'),
                'description' => $schema->string()->nullable()
                    ->description('The description in the target language, or null.'),
            ],
            validate: static function (array $structured) use ($card): ?ProductCard {
                $name = trim((string) ($structured['name'] ?? ''));

                // A card with no name cannot be shown, so an answer without one is not a weak answer,
                // it is an unusable one, and it goes back to the runner as a schema failure.
                if ($name === '') {
                    return null;
                }

                $brand = self::text($structured['brand'] ?? null);

                // **The brand is taken from the INPUT whenever the model changed it.** Rule 1 of the
                // instructions is the one models actually break, and the correct value is already in
                // hand, so enforcing it here costs nothing and makes the prompt's weakest promise
                // something the code guarantees rather than something it asks for.
                //
                // A null answer is different from a changed one: the model declining to repeat a
                // brand is not evidence the brand is wrong, so the input still wins.
                if ($card->brand !== null && $brand !== $card->brand) {
                    $brand = $card->brand;
                }

                return new ProductCard(
                    name: $name,
                    brand: $brand,
                    // An input that had no description cannot gain one here. Rule 3 again, enforced
                    // rather than requested.
                    description: $card->description === null ? null : self::text($structured['description'] ?? null),
                );
            },
        );
    }

    private static function text(mixed $value): ?string
    {
        if (! is_string($value)) {
            return null;
        }

        $value = trim($value);

        return $value === '' ? null : $value;
    }
}
