<?php

/**
 * Which models each AI category may use, in order, and what a token costs.
 *
 * Separate from `config/ai.php`, which belongs to `laravel/ai` and defines PROVIDER CONNECTIONS (keys,
 * URLs). This file defines our own routing on top of them, so a package upgrade republishing its
 * config cannot silently drop our chains.
 *
 * ### Why a chain of ENTRIES rather than a list of models (D76, D77)
 *
 * Two fallback mechanisms exist and they catch different failures, so both are used:
 *
 * - Inside one entry, `models` is OpenRouter's own array. It resolves context-length rejections,
 *   moderation flags, rate limits and downtime INSIDE a single HTTP call, and the request is billed
 *   at whichever model answered. Verified from OpenRouter's own documentation, which also says the
 *   answering model comes back in the response's `model` attribute, which is why usage accounting
 *   reads the response rather than the request.
 * - Across entries, our own loop resolves what OpenRouter cannot see: a 200 carrying JSON that fails
 *   our schema is a perfectly successful request to it. Our loop also crosses a PROVIDER boundary,
 *   and writes one `ai_usage_events` row per attempt (D78).
 *
 * So an entry is `(provider, [models])`, never a bare model string. Adding a second provider to a
 * category is a new entry, not a reshape.
 *
 * ### The models were measured on our own task, not chosen from a leaderboard
 *
 * `ai-design.md` says the model choice is settled by a bake-off rather than a vendor claim. Three
 * measurements decided these, and each contradicted something that looked obvious:
 *
 * 1. **Reasoning defaults dominate latency.** `deepseek-v4-flash-0731` reasons at HIGH effort by
 *    default, which made a translation take 34s and cost 5x. With reasoning off it is 2.6s. Any model
 *    added here must have `reasoning` set deliberately, or the measurement is of a setting.
 * 2. **One sample is not a measurement.** `upstage/solar-pro4` was the cheapest and looked clean on a
 *    single run; over six it failed three. It is not in any chain.
 * 3. **Turkish diacritics separate the vision models hard.** On real product photographs the cheap
 *    tier read `Beypazarı` as "Beypazara" and "Beypazan", and `Ülker` as "İlker". Only
 *    `gemini-3.5-flash-lite` read both correctly, so the vision category pays 4x on purpose: a wrong
 *    brand is a card the user has to correct, which spends their time to save our cents.
 */
return [

    /**
     * The kill switch `legal-and-privacy.md` asks of every external source: no model call leaves the
     * process when this is false, and every gateway degrades to its manual path rather than erroring.
     */
    'live' => env('AI_LIVE', true),

    /**
     * One entry per CATEGORY, which is finer than a gateway on purpose: `ProductEnrichmentGateway`
     * translates text and reads photographs, and those two jobs do not want the same model.
     */
    'categories' => [

        /**
         * Translating a catalogue card into the tenant's locale, and expanding a typed product name.
         *
         * Latency-weighted, because this runs while a user is standing at a shelf with a scanner open.
         *
         * **These were re-measured against the EXACT instructions this gateway sends**, and that
         * reversed the order. A first bake-off used a paraphrase of the prompt and ranked
         * `nemotron-3.5-lightning` first on speed; against the real one it returns the name still in
         * the SOURCE language on two cases of three, and `glm-4.7-flash` fails all three. Neither is
         * in a chain now. A model is fast at a task it is not doing.
         *
         * Against the shipped prompt, three of three clean on brand, units and the "null rather than
         * invent" trap: `gemini-2.5-flash-lite` (907/1651/926ms), `gemini-3.5-flash-lite`
         * (1093/918/842ms, 4x the price) and `deepseek-v4-flash-0731` (2821/4671/10768ms).
         *
         * So the cheap fast one leads, and deepseek is where OpenRouter falls to: it is correct and
         * the cheapest of the three, and its tail is too long to be asked first on a path a person is
         * waiting on.
         */
        'enrichment_text' => [
            // Above the slowest clean response measured on the primary (1651ms) with room, and below
            // what a person reads as the app having hung. A miss costs the translation, never the
            // answer: the cascade falls back to the card in its original language.
            'timeout_ms' => (int) env('AI_ENRICHMENT_TEXT_TIMEOUT_MS', 3000),
            'reasoning' => false,
            'chain' => [
                ['provider' => 'openrouter', 'models' => [
                    'google/gemini-2.5-flash-lite',
                    'deepseek/deepseek-v4-flash-0731',
                ]],
                ['provider' => 'openrouter', 'models' => [
                    'google/gemini-3.5-flash-lite',
                ]],
            ],
        ],

        /**
         * Reading a product photograph into a card.
         *
         * Accuracy-weighted despite `ai-design.md` calling product recognition cost-weighted, and the
         * measurement is why: the cheap tier does not merely cost less, it reads Turkish brand names
         * wrong. The cost weighting still applies WITHIN the models that read the packaging correctly.
         */
        'enrichment_vision' => [
            'timeout_ms' => (int) env('AI_ENRICHMENT_VISION_TIMEOUT_MS', 8000),
            'reasoning' => 'minimal',
            'chain' => [
                ['provider' => 'openrouter', 'models' => [
                    'google/gemini-3.5-flash-lite',
                ]],
                ['provider' => 'openrouter', 'models' => [
                    'google/gemini-2.5-flash-lite',
                ]],
            ],
        ],
    ],

    /**
     * Micro-USD per MILLION tokens, so the cost of a call is integer arithmetic all the way to the
     * `cost_micro_usd` column and nothing is a float that drifts when summed over a million rows.
     *
     * A model absent from this table still runs; its cost is recorded as null rather than as zero,
     * because a zero here would read as "this call was free" in the report `monetization.md` needs.
     */
    'pricing' => [
        'nvidia/nemotron-3.5-lightning' => ['input' => 100_000, 'output' => 250_000],
        'deepseek/deepseek-v4-flash-0731' => ['input' => 80_000, 'output' => 180_000],
        'z-ai/glm-4.7-flash' => ['input' => 60_000, 'output' => 400_000],
        'google/gemini-2.5-flash-lite' => ['input' => 100_000, 'output' => 400_000],
        'google/gemini-3.5-flash-lite' => ['input' => 300_000, 'output' => 2_500_000],
    ],
];
