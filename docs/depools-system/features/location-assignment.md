# Feature: automatic location assignment

> Summary depth. Deepens after the design mockups settle the interaction decisions.

When a product is added, propose where it goes, from the user's own location hierarchy, and be able to say why.

Decisions D9 and D10 in `open-decisions.md`.

## The scenario this is built for

A user has a pantry cabinet. One drawer holds rice and bulgur. The user adds pasta. The system should propose that drawer, and should be able to say:

> Bu çekmeceyi öneriyorum, çünkü bulgur ve pirinç de burada.

## The signal is contents, not names

The obvious approach is to match the product against location names. It mostly does not work, because the drawer holding rice and bulgur is as likely to be called "Çekmece 2" as "Bakliyat Çekmecesi". The name carries no information.

What carries information is what is already stored there. So the primary signal is co-location affinity: for a product in category `c`, score each location `l` by how many category-`c` items already live there.

```
score(l | c) = count(category c items currently in l) / count(category c items anywhere)
```

That is the entire model. It has four properties that matter more than sophistication:

1. **No training.** It is a count table (`location_category_affinity`), updated on write.
2. **Instant adaptation.** A correction changes the next suggestion immediately, because the model is a live count rather than a trained artifact.
3. **Self-explaining.** The numerator *is* the explanation. "Bulgur ve pirinç de burada" is literally what was counted.
4. **Cheap.** No embedding call, no model call, no latency.

This is the same shape as affinity-based warehouse slotting and as Bayesian spam filtering: per-user counts, updated per correction, no retraining step.

### Fallbacks, in order

1. **Co-location affinity**, when the category has been placed before.
2. **Location name semantics**, when a location is new or empty. Keyword match, or embedding similarity between the product text and the location name.
3. **Most recently used location**, when neither applies.
4. **Ask**, with no suggestion, when the tenant has fewer than two locations.

The shared category taxonomy (see `barcode-and-catalog.md`) is what makes step 1 possible across tenants at cold start. Without a shared vocabulary, a brand new tenant has no signal at all.

## The automation dial

A user-set preference, per D10, changeable at any time and per action type.

| Level | Behaviour |
|---|---|
| `manual` | No suggestion. The user picks the location. |
| `semi-auto` | A location is proposed with a visible reason. The user confirms or overrides. |
| `full-auto` | The location is assigned without asking. Undoable, and recorded in the activity feed. |

Two rules that are not negotiable:

- **Manual is a permanent option**, not an onboarding state to graduate from. Shipping auto-categorisation with no opt-out reliably triggers user revolt, and Google Photos users cite both accuracy failures and opacity as reasons to turn auto-tagging off.
- **Full-auto is gated on a measured reversion rate**, not a predicted confidence score. If the tenant's corrections for this action exceed the threshold, the action drops back to semi-auto and the user is told why. Confidence scores are not calibrated when a category has two examples, so measuring what actually happened beats predicting what will.

## Learning from a correction

When the user overrides a suggestion:

```
count(category, suggested_location) -= 1   (floored at zero)
count(category, chosen_location)    += 1
```

That is the whole feedback loop. No batch job, no retraining, and the very next suggestion for that category reflects it.

## Multi-location splits

"3 in the garage, 2 in the kitchen" is a normal case, not an edge case. Capture accepts multiple location and quantity pairs for one product, each creating its own lot. Suggestion proposes the top location for the whole quantity and lets the user split from there, because splitting is a deliberate act and guessing a split would be presumptuous.

## Error and empty states

- **Fewer than two locations.** No suggestion. Offer to create a location instead, since a suggestion between one option is theatre.
- **New category, no history.** Fall back to name semantics, then to most recently used. Say which, if the user asks.
- **Suggested location deleted between suggestion and commit.** Re-suggest rather than error.
- **Full-auto assigned wrongly.** One-tap undo from the activity feed, which also feeds the correction back.
- **Tie between locations.** Prefer the more recently used, and show both.

## Quota effects

None. This is arithmetic over the tenant's own rows.

The optional explanation sentence can go through `PlacementExplanationGateway` for nicer phrasing, but a template renders it for free and that is the default. Paying a model to say "bulgur ve pirinç de burada" is not a good trade.

## Acceptance criteria

1. A tenant with 20 items across 4 locations gets a suggestion accepted without change more than half the time.
2. Every suggestion carries a human-readable reason naming actual items or an actual matched word.
3. An override changes the very next suggestion for that category.
4. Manual level produces no suggestion anywhere in the UI.
5. Full-auto assignments are all visible in the activity feed and all undoable.
6. A tenant with one location and no history is never shown a suggestion.
7. The affinity table never leaks across tenants. Tested.

## Open

- The reversion-rate threshold for demoting full-auto. No published universal number exists; one source suggests 5 percent for a task. Needs a starting value and instrumentation to tune it.
- Whether the dial is one global setting or per action type (location, category, unit). Per action is more correct and more complex; design should decide.
- Whether embedding similarity for the name fallback is worth its cost and latency, or whether keyword matching is sufficient. Measure before adding.
- How to show the reason without cluttering. It matters most on the first few suggestions and becomes noise once the user trusts it.
