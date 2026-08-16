<?php

namespace App\Ai\Contracts;

use App\Ai\IconHint;

/**
 * Reading a place's name well enough to look up a glyph for it.
 *
 * **This feature is the reason the gateway rule exists.** `ProductEnrichmentGateway`'s docblock says
 * it out loud: the MVP's icon-suggestion endpoint called a model directly and escaped the quota
 * system entirely, which is why `ai-enrichment.md` makes "no code path calls a model outside a
 * gateway" an acceptance criterion verified by test. So this interface is not paperwork around a
 * small call; it is the one place the codebase has already been burned.
 *
 * ### Why a model is needed at all, measured rather than assumed
 *
 * The catalogue's own search works in English after its vocabulary fix and finds nothing in Turkish,
 * because no icon set anywhere publishes Turkish tags. What settled it was not the misses:
 *
 *     freezer   -> ac_unit        pantry -> dining
 *     Buzdolabı -> (nothing)      Kiler  -> (nothing)
 *     Depo      -> savings, warehouse, local_atm
 *
 * That last row is worse than a miss. `Depo` matches `savings` because "depo" is a substring of
 * "deposit", and it ranks ABOVE `warehouse`. A substring search on a foreign word does not merely
 * fail to find, it answers confidently and wrongly, so hoping trigrams generalise is not an option.
 *
 * ### Not embeddings
 *
 * The earlier plan was a vector search and measurement killed it: `config/ai_gateways.php` has no
 * embedding entry, [ModelCaller] is structured-output only, and nothing here has ever produced an
 * embedding despite `global_products` carrying a `vector(1536)` column. A structured call reuses the
 * chain, the credit check, the usage record and the redaction that already exist.
 */
interface IconSuggestionGateway
{
    /**
     * Words to look an icon up by, or null when there is no usable answer.
     *
     * **Null is an ordinary outcome, not an error**, exactly as it is on [ProductEnrichmentGateway]:
     * no credit, a refusal, a timeout, a malformed response and the kill switch all arrive here as
     * null. The caller falls back to the neutral icon and the picker, which stay one tap away.
     *
     * @param  string  $subject  a place's name as the user typed it, in any language
     */
    public function suggest(string $subject): ?IconHint;
}
