<?php

namespace App\Ai;

/**
 * What a model made of a place's name: English words to look up, and how sure it is.
 *
 * **Not an icon.** The model never names one, and that is the division `AGENTS.md` draws: it handles
 * language and judgement, deterministic PHP does the lookup and the ranking. A model asked for an
 * icon name would answer with a plausible identifier that does not exist in the catalogue, and
 * nothing in the response would say so.
 *
 * The terms are ORDERED, best first, and that order is the model's own reading of the name. It is
 * kept rather than flattened into one popularity ranking: for "Derin dondurucu" the model returns
 * `freezer` before `refrigerator`, and merging both term's matches by popularity would put the
 * common fridge glyph above the freezer one, which is the answer the specific term exists to avoid.
 */
final readonly class IconHint
{
    /**
     * @param  list<string>  $terms  English search words, best first
     * @param  float  $confidence  0 to 1, the model's own reading of how well the name describes a thing
     */
    public function __construct(
        public array $terms,
        public float $confidence,
    ) {}
}
