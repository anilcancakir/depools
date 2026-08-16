<?php

namespace App\Services;

use App\Ai\Contracts\IconSuggestionGateway;
use App\Models\Icon;

/**
 * A place's name in, an icon from the catalogue out, or nothing.
 *
 * **The threshold is the half that matters**, and `GlobalProduct` already records why: a
 * nearest-neighbour query always returns a top hit however wrong, while a threshold query can return
 * nothing. An icon suggestion has the same shape. Every name resolves to SOME glyph if you let it,
 * and a confidently wrong one is worse than none: the user accepts a default they did not read, and
 * the shelf tree then carries a picture that contradicts its own label.
 *
 * So there are two ways to get nothing, and both are ordinary:
 *
 * - the model itself is unsure, which is what the confidence is for;
 * - it was sure and no term matched anything, which is a vocabulary gap in a general-purpose icon
 *   set rather than a bad read of the name.
 *
 * Either way the caller uses [Icon::FALLBACK] and the picker stays one tap away. The suggestion is a
 * DEFAULT, never a decision.
 */
final readonly class IconSuggester
{
    /**
     * Below this, the answer is nothing.
     *
     * **0.6 rather than a half, and the instructions are what make the number meaningful.** They
     * anchor a describable name at 0.9 and up and a bare code at 0.3 and down, so the band this cuts
     * through is deliberately empty: it separates the two clusters the prompt asks for rather than
     * trying to grade a continuum. A model asked for a confidence with no anchor answers 0.9 to
     * everything, and against that any threshold at all is decoration.
     */
    public const MIN_CONFIDENCE = 0.6;

    public function __construct(private IconSuggestionGateway $gateway) {}

    /**
     * The icon for a name, or null when there is no answer worth defaulting to.
     *
     * **The terms are walked in the model's own order and the first match wins**, rather than every
     * term's matches being pooled and ranked by popularity together. Popularity is the right
     * tiebreaker WITHIN one word, which is what `Icon::matching` uses it for; across words it is the
     * wrong instrument, because a generic later term always has more popular matches than a specific
     * first one. "Derin dondurucu" returns `freezer` then `refrigerator`, and pooling them would
     * hand back the fridge.
     */
    public function forName(string $name): ?Icon
    {
        $name = trim($name);

        if ($name === '') {
            return null;
        }

        $hint = $this->gateway->suggest($name);

        if ($hint === null || $hint->confidence < self::MIN_CONFIDENCE) {
            return null;
        }

        foreach ($hint->terms as $term) {
            $icon = Icon::matching($term)->first();

            if ($icon !== null) {
                return $icon;
            }
        }

        return null;
    }
}
