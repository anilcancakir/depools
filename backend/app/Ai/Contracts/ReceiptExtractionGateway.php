<?php

namespace App\Ai\Contracts;

use App\Ai\ExtractedReceipt;
use App\Ai\ImageInput;

/**
 * Reading a photographed receipt into line items.
 *
 * The second of the five gateways `ai-design.md` names, and the first caller in this codebase that
 * sends an IMAGE: `enrichment_vision` has been configured since the enrichment work and nothing has
 * ever called it, so this is where the image half of the substrate earns its keep.
 *
 * ### Accuracy-weighted, unlike product recognition
 *
 * `ai-design.md` splits the two vision paths deliberately. A wrong product card is visible
 * immediately, because the user is already looking at it. A wrong receipt line becomes wrong stock
 * the user may not notice for weeks, which is the failure that sank the previous MVP's credibility.
 * So this category is allowed to be slower and dearer than `enrichment_vision`, and its chain is
 * ordered accordingly.
 *
 * ### It reads, it does not resolve
 *
 * The answer carries the till's own abbreviations (`PNR SUT 1LT`) and no product ids. Turning a
 * printed string into a real product is a separate, cheaper-first pipeline, and it stays separate
 * because it must be allowed to say "I do not know, ask the user": `receipt-ingestion.md` makes
 * per-line confirmation mandatory, and a gateway that resolved as it read would hand the review
 * screen a decision already made.
 */
interface ReceiptExtractionGateway
{
    /**
     * The receipt in [$image], or null when nothing usable came back.
     *
     * **Null is an ordinary outcome**, as it is on every gateway here: no credit, a refusal, a
     * timeout, a malformed response and the kill switch all arrive as null, and the caller falls
     * back to the manual path that `receipt-ingestion.md` requires to stay open.
     *
     * A photograph the model could not read is also null rather than an empty result. "Unreadable,
     * retake it" and "this receipt genuinely has no lines" are different screens, and an empty list
     * would collapse them into one.
     */
    public function extract(ImageInput $image): ?ExtractedReceipt;
}
