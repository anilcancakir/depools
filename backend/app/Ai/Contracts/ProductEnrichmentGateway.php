<?php

namespace App\Ai\Contracts;

use App\Ai\GatewayAttempt;
use App\Ai\ImageInput;
use App\Ai\ProductCard;
use App\Ai\RecognisedProduct;
use Closure;

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
 * The typed-name entry point is still absent, for the reason the photograph one used to be: a method
 * nobody calls yet would be a shape guessed before its caller exists. `ai-design.md` names three
 * inputs for this one interface (a name, a photo, a barcode), and a second interface for the photo
 * would have made it four against that table's five.
 */
interface ProductEnrichmentGateway
{
    /**
     * The card a photograph of a product yields, or null when it could not be produced.
     *
     * Null is an ordinary outcome here for the same reasons as below, plus one of its own: a
     * photograph of a shelf, a person or a blank wall is a picture with no single product in it, and
     * a gateway that answered anyway would be inventing the card the caller is about to show.
     *
     * @param  Closure(GatewayAttempt): void|null  $onAttempt  told about each attempt as it
     *                                                         lands, so the caller can record
     *                                                         which model answered
     */
    public function recognise(ImageInput $image, ?Closure $onAttempt = null): ?RecognisedProduct;

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
