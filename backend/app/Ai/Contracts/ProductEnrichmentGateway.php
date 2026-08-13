<?php

namespace App\Ai\Contracts;

use App\Ai\ProductCard;

/**
 * Turning as little as the user gave us into a product card.
 *
 * **The interface exists so there is no path around it** (`ai-design.md`, `architecture.md`). Every
 * implementation runs redaction, checks the tenant's credit balance, records an `ai_usage_events`
 * row per attempt and validates the response against its schema, and a caller reaching a model
 * directly would skip all four. The MVP's icon-suggestion endpoint did exactly that and escaped the
 * quota system entirely, which is why `ai-enrichment.md` makes "no code path calls a model outside a
 * gateway" an acceptance criterion verified by test rather than a convention.
 *
 * Only the translation entry point is declared here. The photograph and typed-name entry points
 * arrive with the screens that need them; a method nobody calls yet would be a shape guessed before
 * its caller exists.
 */
interface ProductEnrichmentGateway
{
    /**
     * The same card in another language, or null when it could not be produced.
     *
     * **Null is an ordinary outcome, not an error**, and every caller has to treat it that way: no
     * credit, the model refusing, a timeout, a malformed response and the kill switch all arrive
     * here as null. `ai-enrichment.md` requires the manual path to stay fully functional with zero
     * credits, so a gateway that threw would make the feature's failure the caller's problem.
     *
     * @param  string  $targetLocale  a two-letter language code, e.g. `tr`
     */
    public function translate(ProductCard $card, string $targetLocale): ?ProductCard;
}
