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
         *
         * **This chain deliberately did NOT follow `receipt_extraction` onto `gemini-3.1-flash-lite`,
         * and the reason is that the receipt bake-off measured a different job.** A receipt is
         * monospaced glyphs on a known layout; packaging is a photograph of a curved surface with
         * brand typography on it, which is why these are two categories rather than one. The receipt
         * result narrows the shortlist and settles nothing here. Moving this chain wants its own
         * bake-off over real product photographs, scored on brand and unit rather than on line items,
         * and `bin/receipt-bakeoff/` is the harness to fork for it: the scenario file and the schema
         * are the only parts that change.
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

        /**
         * Reading a photographed receipt into line items.
         *
         * **Its own category rather than a second caller on `enrichment_vision`**, because
         * `ai-design.md` splits the two vision paths on what a wrong answer costs. A wrong product
         * card is visible immediately, with the user already looking at it. A wrong receipt line
         * becomes wrong stock nobody notices for weeks, so this one is allowed to be slower and
         * dearer and its chain is ordered on accuracy rather than on price.
         *
         * **Measured, on this gateway's own prompt and schema, against ten receipts whose ground
         * truth we hold.** Eleven candidates, 120 calls, $0.19 billed. Five scored a perfect 100
         * and the ranking below is therefore decided on cost and latency rather than on accuracy,
         * which is the honest reading of it:
         *
         * | model                        | score | $/receipt | p50    | p95     |
         * |------------------------------|-------|-----------|--------|---------|
         * | gemini-3.1-flash-lite @min   | 100.0 | 0.0017    | 3258ms |  4091ms |
         * | gemini-3.5-flash-lite @min   | 100.0 | 0.0027    | 3034ms |  4048ms |
         * | gemini-3-flash-preview       | 100.0 | 0.0031    | 6482ms | 15748ms |
         * | glm-5.3-flash                |  99.2 | 0.0009    |  14.8s |   20.9s |
         * | qwen3-vl-32b                 |  97.9 | 0.0006    | 7567ms | 10284ms |
         * | gpt-5.4-nano                 |  92.3 | 0.0018    | 8686ms | 17857ms |
         * | deepseek-v4-flash-vision-exp |  87.4 | 0.0021    |  14.4s |  18.3s  |
         * | gemini-2.5-flash-lite        |  87.1 | 0.0011    | 8548ms | 10907ms |
         *
         * So `gemini-3.1-flash-lite` leads: the same perfect score as the model it replaces, at 63%
         * of the cost, and it is the only Gemini here that honours rule 6 (dot decimals) rather
         * than leaning on the gateway's own comma conversion. `3.5-flash-lite` stays behind it
         * because it also scored 100 and holds the best p95 in the whole set.
         *
         * **Three candidates were rejected on accuracy, and the reason is one rule rather than
         * OCR.** `qwen3-vl-32b` (the cheapest that works), `deepseek-v4-flash-vision-exp` and
         * `gpt-5.4-nano` all ADD Turkish diacritics the till never printed: `KASAR PEYNIR` came
         * back as `KAŞAR PEYNIR`, `SALCA` as `SALÇA`, `GAZOZ` as `GAZÖZ`. That is rule 1 broken by
         * being helpful, and it is expensive downstream, because the resolver matches the raw
         * string: a corrected name misses the catalogue entry keyed on the printed one. Note the
         * DIRECTION, which is the opposite of what `enrichment_vision` measured on packaging:
         * there the cheap tier dropped diacritics, here the cheap tier invents them.
         *
         * **Two are unusable through this gateway whatever they score.** `qwen3.5-flash-02-23` and
         * `qwen3.6-plus` fail 10 of 10 with HTTP 400: their only OpenRouter provider downgrades
         * `json_schema` to `json_object` and then demands the word "json" in the prompt.
         * `provider: {require_parameters: true}` does not rescue them, there being no second
         * provider. OpenRouter's own metadata advertises `structured_outputs` for both, so that
         * field says a provider ACCEPTS the parameter, not that it honours it.
         *
         * Reasoning is `minimal` rather than `low`. Both chain entries were measured at both levels
         * and score 100 either way, so the tie breaks on cost and latency, and minimal wins both on
         * the primary. It also matches socOCRbench, which scores this model higher at minimal than
         * at low. Gemini 3.x cannot disable thinking entirely, so minimal is the floor rather than
         * off.
         *
         * **O2 is still open and this does not close it.** The receipts were RENDERED, not
         * photographed: crisp glyphs, one degraded case out of ten, no real thermal paper, no
         * glare, no curl. Five perfect scores is the tell that the set does not discriminate at the
         * top. Two findings that ReceiptBench reports for this model family also failed to
         * reproduce here, and it is worth knowing which way that cuts: nobody tampered with the
         * total we deliberately printed wrong (`499,99` against a line sum of `520,05`) and nobody
         * swapped a day for a month. Either rules 2 and 7 above are earning their place or the
         * paper was too clean, and the way to tell them apart is an ablation of the prompt rather
         * than another model. The harness lives in `bin/receipt-bakeoff/`.
         */
        'receipt_extraction' => [
            // **Far above the vision default, and it buys the acceptance criterion rather than
            // patience.** `receipt-ingestion.md` allows 15 seconds from shutter to a confirmable
            // list, and that budget covers the upload, the downscale, this call and the resolution
            // pass. A 25-line receipt is a much longer answer than a product card, so the timeout
            // that fits one does not fit the other.
            'timeout_ms' => (int) env('AI_RECEIPT_EXTRACTION_TIMEOUT_MS', 20000),
            'reasoning' => 'minimal',
            'chain' => [
                ['provider' => 'openrouter', 'models' => [
                    'google/gemini-3.1-flash-lite',
                ]],
                ['provider' => 'openrouter', 'models' => [
                    'google/gemini-3.5-flash-lite',
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
     *
     * **A hand-kept price table goes stale silently, and two of these had.** Read against
     * OpenRouter's own `/api/v1/models` on 2026-09-02, `nemotron` was 20% over on both columns and
     * `deepseek-v4-flash-0731` was 23% over on input, which matters because that one IS in a chain:
     * every call it answered overstated `cost_micro_usd`, in the one column
     * `monetization.md` asks "what does this tenant cost us" of. Every row below was re-read at the
     * moment it was written. Re-read them before trusting a cost report, with:
     *
     *     curl -s https://openrouter.ai/api/v1/models | python3 -c "..."
     *
     * `nemotron` and `glm-4.7-flash` are priced and in no chain on purpose: the docblock at the top
     * names them as measured and rejected, and a price keeps that comparison readable.
     */
    'pricing' => [
        'nvidia/nemotron-3.5-lightning' => ['input' => 80_000, 'output' => 200_000],
        'deepseek/deepseek-v4-flash-0731' => ['input' => 65_000, 'output' => 180_000],
        'z-ai/glm-4.7-flash' => ['input' => 60_000, 'output' => 400_000],
        'google/gemini-2.5-flash-lite' => ['input' => 100_000, 'output' => 400_000],
        'google/gemini-3.1-flash-lite' => ['input' => 250_000, 'output' => 1_500_000],
        'google/gemini-3.5-flash-lite' => ['input' => 300_000, 'output' => 2_500_000],
    ],
];
