# Feature: AI product enrichment

> Summary depth. Deepens after the design mockups settle the interaction decisions.

Fill in a product card from as little as the user gave us: a photograph, a name, or a barcode.

This is the one area where the previous MVP was genuinely strong, and most of its design survives. Decision D6 and the cost model in `ai-design.md`.

## What it does

Four entry points, one output shape.

| Input | Output |
|---|---|
| A photograph of a product | name, brand, description, category, unit hint |
| A product name the user typed | brand, description, category, tags |
| A barcode that resolved to a foreign-language catalog entry | the same fields, translated to the tenant locale |
| A photograph of a shelf | multiple candidate products, each as a card |

Everything goes through `ProductEnrichmentGateway`. The output is always a **draft card the user confirms**, never a silent write.

## Why it is table stakes, not a differentiator

Every AI-native household inventory app ships photo-to-item recognition, and Kept gives it away at 19.99 USD per year. So this feature earns no premium. It exists because a product without it feels broken in 2026, and because it is the fastest path from "I have a thing" to "the thing is in stock".

The differentiation is what happens after: the ledger, the expiry tracking, the location suggestion, the forecast. This feature feeds those.

Positioned accordingly in `monetization.md`: enrichment is available on every tier including free, metered by credits.

## Flow

1. The user provides a photo, a name, or arrives from a barcode miss.
2. A draft product card is created immediately and shown as incomplete. Nothing waits on the model before the user sees something.
3. The gateway runs: redaction, credit check, model call with a JSON schema, validation, usage recording.
4. Fields populate progressively as they arrive. Streaming matters here; the MVP had none and users watched a blank screen through image analysis.
5. The user edits anything, then saves.
6. Category resolves against the shared taxonomy. Location is suggested. Stock quantity is asked.

## Constraints that keep it honest

- **A suggested category must exist in the taxonomy.** The MVP validated the model's category answer against the tenant's real list and returned null on a miss, which is exactly right and is kept.
- **Uncertainty is null, not a guess.** If the model cannot read the brand, the field stays empty. The MVP instructed the model to return the literal string "unknown" and then stripped it, which worked but was fragile; a schema with nullable fields expresses it properly.
- **Every field is editable before commit.** No field is locked because the model was confident.
- **No fake latency.** A cache hit returns instantly. The MVP added `sleep(rand(2,3))` on cache hits in four places to simulate work, one commented `// Simulate processing time`. That is a small lie and it goes.

## Caching

Two distinct caches, keyed separately, which the MVP conflated into one column:

- **Image cache**: perceptual hash of the downscaled image, so re-photographing the same product costs nothing.
- **Name cache**: normalised name hash, so the same typed name costs nothing.

Both are scoped per locale, because the same product needs a different card in Turkish and English.

The MVP wrote a perceptual image hash and an md5 of the product name into the same `hash` column, so nothing downstream could tell which kind of hash it was reading. Two columns now (`image_phash`, `name_hash`).

## The shelf photo case

"Photograph a shelf, add everything you see" is a real request and needs a different UI from single-item capture: a film strip of detected candidates, each tappable to review, with a count and a bulk accept.

Every product studied that supports it (Manifest, MovingBox) routes it through a batch review step rather than committing directly. Same rule here.

## Error and empty states

- **Nothing recognisable.** Say so and offer manual entry. Do not return a plausible invention.
- **Malformed model response.** Retry once with a stricter instruction, then fall back to manual. Never surface a parse error.
- **Partial recognition.** Fill what was found, leave the rest empty, and let the user finish. This is the common case, not a failure.
- **Credits exhausted.** Manual entry is fully functional. The card is created either way.
- **Photo too large or unreadable.** Reject with a reason before spending a credit.
- **Multiple candidates from one photo.** Present them, let the user choose, do not pick silently.

## Quota effects

- One credit per model call. A cache hit costs nothing and says so.
- Barcode-driven translation of an existing catalog entry consumes a credit only when the target locale is genuinely missing.
- A shelf photo is one credit regardless of how many items it yields, which makes it the most economical capture path and is worth telling users.

## Acceptance criteria

1. A photograph of a common Turkish grocery product produces a card the user saves with at most one edit.
2. The user sees a draft card within one second, before the model responds.
3. Re-photographing the same product returns instantly and consumes no credit.
4. A category the model invents is rejected and the field is left empty.
5. With zero credits, manual product creation still works end to end.
6. No code path anywhere calls a model outside a gateway. Verified by test, because the MVP's icon endpoint did exactly that and escaped quota entirely.
7. No artificial delay exists in any path.

## Open

- Which model per entry point. Product recognition weights cost, receipt extraction weights accuracy, and they may not be the same model (O2).
- Whether tag generation is worth keeping. The MVP had a dedicated agent for it, but tags may be redundant now that a real shared category taxonomy exists. Design should decide whether users actually use tags when categories are good.
- Whether the shelf photo case is v1 or v2. It needs its own review UI, which is real design work.
- How many items one shelf photo should attempt. Too many and the review becomes a chore, too few and the feature disappoints.
