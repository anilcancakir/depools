<?php

namespace App\Ai\LaravelAi;

use App\Ai\Contracts\ProductEnrichmentGateway;
use App\Ai\GatewayRunner;
use App\Ai\ImageInput;
use App\Ai\ProductCard;
use App\Ai\RecognisedProduct;
use App\Support\UnitHint;
use Closure;
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
     * The instructions for translating a card, which are mostly a list of things not to do.
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
    private const TRANSLATE_INSTRUCTIONS = <<<'TXT'
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

    /**
     * The instructions for reading a photograph, which are a different list of things not to do.
     *
     * The translation rules above defend a card that already exists. These defend one that does not,
     * so the failure they guard against is invention rather than drift:
     *
     * - **Brands again, and for a measured reason.** `enrichment_vision`'s own bake-off found the
     *   cheap tier reading `Beypazarı` as "Beypazara" and `Ülker` as "İlker", which is why that
     *   category pays four times as much per call. The prompt cannot fix a model that misreads a
     *   diacritic, but it can stop one that reads it correctly from tidying it away afterwards.
     * - **The name excludes the brand**, because the card carries them in two fields and a model
     *   left to itself puts the brand in both. `Pınar` plus `Süt Tam Yağlı 1 L`, never `Pınar Pınar
     *   Süt`.
     * - **The unit is what you COUNT.** A box saying "500 g" is describing its contents, and a model
     *   asked for "the unit" will answer grams. [UnitHint] has no gram in it for exactly this
     *   reason, and the instruction says the same thing in words so the closed list is not the only
     *   thing carrying it.
     * - **A photograph with no single product in it returns a null name.** A shelf, a room, a person
     *   or a receipt is not a product card, and a model asked to describe a picture will always
     *   describe it.
     */
    private const RECOGNISE_INSTRUCTIONS = <<<'TXT'
        You read a photograph of a single retail product for an inventory application.

        The photograph is usually of grocery packaging, often Turkish, held in one hand.

        Rules, in order of importance:
        1. Report only what is PRINTED ON THE PACKAGING. Never infer a detail from the product
           category, from what such a product usually contains, or from what the brand usually
           sells. If it is not legible in the photograph, the field is null.
        2. Copy the BRAND verbatim, exactly as printed, with its own diacritics and casing. A brand
           is a proper noun: never translate, transliterate, correct or re-case it.
        3. The name is the product WITHOUT the brand. The brand has its own field and repeating it
           in both is wrong.
        4. The unit is what a person COUNTS, not what the package contains. A 500 g bag of rice is
           counted in bags; the 500 g belongs to the contents and not here. Answer with one word
           from the list you are given, or null if none of them fits.
        5. The category is a short, ordinary phrase for what kind of thing this is, in English,
           lower case. It is checked against a fixed taxonomy afterwards, so a phrase that is not in
           it is dropped: a plain common noun beats a clever one.
        6. If the photograph does not show ONE product, return null for the name. A shelf of
           several products, a room, a person, a receipt, a screen or a blank surface all get a null
           name rather than a description of what is there.
        TXT;

    public function __construct(private readonly GatewayRunner $runner) {}

    public function recognise(ImageInput $image, ?Closure $onAttempt = null): ?RecognisedProduct
    {
        return $this->runner->run(
            category: 'enrichment_vision',
            instructions: self::RECOGNISE_INSTRUCTIONS,
            // **The prompt carries no content of its own, and that is deliberate.** Everything the
            // model needs is in the photograph and in the instructions; a sentence here describing
            // what we hope to see is a leading question, and the one field this path cannot afford
            // to lead is the brand.
            input: 'Read this product photograph.',
            schema: static fn (JsonSchema $schema): array => [
                'name' => $schema->string()->nullable()
                    ->description('The product name as printed, WITHOUT the brand. Null if the photograph does not show one product.'),
                'brand' => $schema->string()->nullable()
                    ->description('The brand exactly as printed, or null if none is legible.'),
                'description' => $schema->string()->nullable()
                    ->description('One short sentence, only from text printed on the packaging. Null if there is nothing to read.'),
                'category' => $schema->string()->nullable()
                    ->description('A short ordinary English phrase for the kind of product, lower case.'),
                'unit' => $schema->string()->nullable()
                    ->description('What one of these is COUNTED in. Exactly one of: '.UnitHint::words().'. Null if unsure.'),
            ],
            validate: static function (array $structured): ?RecognisedProduct {
                $name = trim((string) ($structured['name'] ?? ''));

                // **Rule 6 arriving as an answer rather than as a failure.** A null name is what the
                // instructions ask for when the photograph holds no single product, and it reaches
                // the runner as a schema rejection because there is no other way to say it: the
                // runner retries once with a stricter prompt and then gives up, which is one wasted
                // call on a photograph of a wall and the honest outcome on a genuinely bad read.
                if ($name === '') {
                    return null;
                }

                return new RecognisedProduct(
                    name: $name,
                    brand: self::text($structured['brand'] ?? null),
                    description: self::text($structured['description'] ?? null),
                    categoryName: self::text($structured['category'] ?? null),
                    // Passed through as the WORD, not resolved here. This class holds the prompt and
                    // the schema and nothing else, and resolving a hint against a database would be
                    // the first query it ever made.
                    unitHint: self::text($structured['unit'] ?? null),
                );
            },
            image: $image,
            onAttempt: $onAttempt,
        );
    }

    public function translate(ProductCard $card, string $targetLocale): ?ProductCard
    {
        return $this->runner->run(
            category: 'enrichment_text',
            instructions: self::TRANSLATE_INSTRUCTIONS,
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
