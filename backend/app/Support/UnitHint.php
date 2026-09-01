<?php

namespace App\Support;

/**
 * The closed list of words a vision model may answer with, and the Rec 20 code each one means.
 *
 * ### Why a word list rather than the codes themselves
 *
 * D126 says `unit` holds a Rec 20 code everywhere, and asking a model for one would be asking it to
 * recall an identifier: `C62` is "one piece" and `H87` is also "one piece", and only the first is
 * seeded. A model that guesses between them produces a 422 from a field the user never filled in.
 * So the model answers in words it can actually read off a box, and the map below is the arithmetic,
 * which is PHP's job rather than the model's.
 *
 * ### What is deliberately absent, and it is the whole point of the list
 *
 * There is no `gram` and no `millilitre`. `ProductCandidate::$unitHint` records the trap: a source
 * that says "500 g" is describing what one pack CONTAINS, not what you count, and a model reading a
 * box will say exactly that. Taking it as the base unit is the mistake the demo seeder shipped, and
 * it makes a 500 g pack read as "2 g" on the count sheet.
 *
 * `kilogram`, `litre` and `metre` survive because loose goods are genuinely counted in them: a
 * greengrocer's tomatoes are kilograms, not pieces. The line is content-versus-count rather than
 * mass-versus-piece, which is why the fine-grained multiples go and their roots stay.
 *
 * Both readers are one method call away from this map: the gateway builds its schema description
 * from [words] and the reader resolves through [toCode], so the prompt and the mapping cannot drift
 * into disagreeing about what a valid answer is.
 */
final class UnitHint
{
    /**
     * Word to Rec 20 code, in the order the prompt should offer them.
     *
     * Countables first, because most of what a photograph shows is counted rather than weighed.
     *
     * @var array<string, string>
     */
    private const CODES = [
        'piece' => 'C62',
        'package' => 'PK',
        'box' => 'BX',
        'carton' => 'CT',
        'case' => 'CS',
        'bag' => 'BG',
        'roll' => 'ROL',
        'set' => 'SET',
        'kilogram' => 'KGM',
        'litre' => 'LTR',
        'metre' => 'MTR',
    ];

    /**
     * The words a model may answer with, comma-separated, for a schema description.
     */
    public static function words(): string
    {
        return implode(', ', array_keys(self::CODES));
    }

    /**
     * The Rec 20 code this word means, or null when it is not one of ours.
     *
     * Null on a miss rather than a fallback to `C62`, and the difference is visible to the user: an
     * unresolved hint leaves the unit field empty and asking, while a silent `piece` would leave it
     * filled, marked as inferred and WRONG for the greengrocer's tomatoes. `ai-enrichment.md` makes
     * this the rule for the category and the reasoning is identical for the unit.
     */
    public static function toCode(?string $word): ?string
    {
        if ($word === null) {
            return null;
        }

        // `strtolower` rather than `mb_strtolower`: since PHP 8.2 it is ASCII-only and no longer
        // reads the locale, which is exactly right for a key set that is ASCII by construction. A
        // model answering in another script does not match, which is the correct answer anyway.
        return self::CODES[strtolower(trim($word))] ?? null;
    }
}
