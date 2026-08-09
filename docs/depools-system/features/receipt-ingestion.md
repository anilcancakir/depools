# Feature: receipt and invoice ingestion

Turn a purchase document into stock. This is the headline capture path and the reason a non-technical user would choose this product.

Decisions D14 and D15 in `open-decisions.md`. Legal position in `legal-and-privacy.md`.

## Two paths, because Turkish law produces two documents

Verified: for 2026 the invoice threshold is 12.000 TL VAT-inclusive, and document type is decided by who the buyer is.

| Situation | Document | Our path | Accuracy |
|---|---|---|---|
| Buyer is an e-fatura registered business | e-Fatura, regardless of amount | Parse UBL-TR 1.2.1 XML | Near perfect, no OCR |
| Individual, under threshold, no invoice requested | Paper ÖKC fiş only | Photograph and extract | Best effort |
| Individual over threshold, or requested an invoice | e-Arşiv Fatura | Parse XML if available, else photograph | Near perfect if XML |

These are not primary and fallback. A business buying from suppliers lives on path one; the same owner running to the market for milk lives on path two. Both are needed.

The threshold is inflation-indexed and changes annually. It is configuration, never a literal.

## Path A: structured XML

The clean path. The user forwards an invoice email to their unique inbound address, or uploads the XML directly.

1. Inbound mail arrives at `fatura+<unguessable-token>@in.depools.ai`.
2. Sender verification: SPF, DKIM, DMARC, plus a per-tenant sender allowlist. Failure means rejection, not filing.
3. UBL-TR XML is located, in the body or an attachment.
4. Line items are parsed deterministically. No model involved, so no cost and no hallucination.
5. Each line resolves to a product (see `barcode-and-catalog.md` for the resolution cascade).
6. The user confirms.

## Path B: photograph

1. The user supplies the receipt image: the camera on a phone, the camera or a file picker in a browser. Same screen, same parse, same review on all three platforms; only the input control differs, because that is a hardware difference and not a feature difference.
2. The image is downscaled and stored, and a `receipts` row is created immediately so the work is never lost.
3. Extraction produces line items with per-line confidence, through `ReceiptExtractionGateway`.
4. Each line's abbreviated name is normalised and resolved (this is the hard part, see below).
5. Location is suggested per line from co-location affinity.
6. **Mandatory per-line confirmation.** The user accepts, edits or rejects each line.
7. Commit writes lots and movements atomically with an idempotency key.

### Why confirmation is mandatory

Every comparable product does this. Kept populates a card and waits. Manifest routes multi-item capture through a review step. Expensify explicitly fails open to manual entry rather than guessing. Bevel states plainly that the user is always in control.

A silently inserted wrong line item becomes wrong stock the user may not notice for weeks, and a wrong number destroys trust faster than an honest request to check.

### The hard part is not OCR

Turkish thermal receipts truncate: "PNR SUT 1LT", "ORG KEM TAV" for "Organik Kemikli Tavuk". Perfect character recognition still leaves a string that must become a real product.

Resolution runs cheapest first: exact match against the tenant's own products, then embedding similarity, then model normalisation with the receipt's other lines as context, then ask the user. Every confirmation the user makes strengthens the first step for next time.

Detail in `ai-design.md`.

## Error and empty states

- **Unreadable photo.** Say so immediately and offer retake or manual entry. Never a partial guess presented as complete.
- **Partial extraction.** 18 of 22 lines resolved is presented as 18 resolved and 4 needing attention, and the receipt stays resumable.
- **Interrupted confirmation.** Per-line state is persisted, so the user returns exactly where they left off.
- **Duplicate receipt.** Detected by image hash and by invoice number, and the user is asked rather than silently blocked, because reprinting a receipt is a real thing.
- **XML that fails schema validation.** Fall back to treating the attached PDF or body as a document to extract, and record why.
- **No AI credits.** The receipt is still created and the user can key it in. Extraction is what stops, not the feature.

## Quota effects

- Photo extraction consumes AI credits, one per receipt regardless of line count.
- XML parsing consumes none. It is deterministic, so it is free, and that asymmetry is worth telling business users about.
- Resolution against our own catalog consumes none.

## Acceptance criteria

1. A Turkish grocery receipt with 15 to 25 lines produces line items the user accepts with edits to fewer than 3 lines.
2. Time from shutter to a confirmable list is under 15 seconds.
3. An e-Fatura XML produces exact line items with zero AI cost.
4. A receipt abandoned mid-confirmation is resumable with no lost work.
5. The same receipt submitted twice does not double stock.
6. Mail spoofed to another tenant's inbound address is rejected.
7. With zero AI credits, the manual path still completes.

## Screens

| Screen | Route | States |
|---|---|---|
| `ReceiptReviewView` | `/fis` | lines with confidence and resolution state |
| forwarding address | `/ayarlar` | the tenant's inbound address, with copy |

## What the design settled

- **It is entered from the overview's capture actions**, beside the barcode scanner and the shelf
  photo, because all three are "point the camera at the thing". Until that existed the screen had no
  way in.
- **Unresolved lines float to the top**, which is the opposite of the scan queue's ordering. The two
  differ for a reason: paper is static and finite, so the user works the exceptions; a scan queue is
  live, so the newest read has to be visible or the user gets no feedback.
- **The forwarding address is a settings section rather than a screen**, because there is nothing to
  do with it but read and copy. It is rendered in mono for the same reason a barcode is: it has to
  be transcribed into a mail rule exactly.
- **Recognition runs server-side**, and that is forced rather than chosen: `mobile_scanner` has no
  `analyzeImage` on web, so a still photo cannot be decoded on the device there at all.

## Open

- Which vision model, decided by a bake-off on 100 real Turkish receipts (O2).
- Whether Turkish senders emit `schema.org/Order` JSON-LD in order emails, and whether e-Arşiv PDFs reliably embed UBL-TR XML. Both unverified (O4). Design must not assume either.
- Which inbound email provider. Cloudflare Email Routing is free for the routing layer; Postmark and Resend offer managed parsing.
- Whether multi-page or long receipts need stitching, which depends on how Turkish receipts photograph in practice.
