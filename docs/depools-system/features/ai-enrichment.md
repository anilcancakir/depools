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

"Photograph a shelf, add everything you see" is a real request and needs a different UI from single-item capture. Every product studied that supports it (Manifest, MovingBox) routes it through a batch review step rather than committing directly. Same rule here.

**The photograph stays on screen with numbered boxes, and every row carries its number** (D60).
This supersedes the film strip this section originally sketched: a strip of crops is the weaker
version of the same idea, because the photograph IS the strip. Drawing boxes on it and numbering
the rows to match gives the spatial link without a second set of images, and it works with no
hover or tap state, which a static review and a screen reader both need.

**The accept button counts products, not regions.** Six regions can yield four products; a button
labelled with the region count would promise to write an unnamed bottle and a price label the
recogniser mistook for stock. Rejecting that label is routine rather than an edge case, so the
rejected state fades and stays rather than disappearing: a candidate that vanished on rejection
could not be un-rejected.

**The read is never a blank screen.** The MVP left users watching nothing through a two-minute
analysis, so the reading state shows the photograph immediately, draws each box as its region
finishes, counts how far it has got, and leaves a skeleton row where the next candidate will
land. A list that stops at four looks finished at four.

**A failed read keeps the photograph.** The picture stays, the callout says what was kept and
that no credit was spent, and both ways forward are offered. The MVP stored the upload before
validating extraction, so a failure left a file with nothing pointing at it.

**Known weakness, recorded rather than hacked around.** The region outlines use
`border-color-border`, a deliberately low-contrast hairline that will vanish over a white shelf
label. The badge carries the annotation for now because it is `bg-primary` and strong.
`border-bg-primary` was tried and dropped silently, since wind's alias expander matches a whole
token against a key and there is no such key. The real fix is a fixed high-contrast overlay
border, listed in DESIGN.md under the tokens this palette still needs.

## Editing a field

Every field opens the same sheet in one of three shapes: free text, a number with its unit,
or a list of options. Nine bespoke editors would be nine things to learn on a screen whose
whole point is that it fills itself in.

The sheet has three parts in a fixed order. **What it is**: the field name and where its
current value came from, because `Fotoğraftan okundu` and `İsteğe bağlı` are different
situations a user cannot tell apart from the field alone. **The quick answers**: chips,
with the current value first, so agreeing costs one tap. **The control**: always present,
because a chip set that cannot be escaped is a wizard.

A choice field gets no chips. Its options list already IS the set of one-tap answers, and a
chip row repeating the first option was the same word twice, eight pixels apart, both
selected. The suggested option carries its reason on the row instead
(`Önerilen · buraya 9 kez konuldu`), the same as every other location picker in the app.

**Saving clears the `otomatik` mark, whether or not the value changed** (D53). A value the
user has looked at and kept is no longer a guess. Dismissing without saving leaves the mark,
because looking is not confirming. So the marks decay as the draft is reviewed rather than
persisting as permanent noise, and the screen gains a natural finish line. The sheet says
this outright above its save button, because a mark disappearing after the user changed
nothing is otherwise a surprise.

**The unit is freely editable here and only here** (D54). A draft has no stock, so nothing
is reinterpreted. Once a movement exists, changing the unit changes what every quantity in
the ledger means, and that is a conversion rather than a field edit.

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
