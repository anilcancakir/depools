# Feature: consumption, expiry and the shopping list

> Summary depth. Deepens after the design mockups settle the interaction decisions.

Tell the user what is running out, what is about to spoil, and what to buy. Without lying to them.

Decisions D7 and D8 in `open-decisions.md`.

## The honesty constraint comes first

A household or a cafe consumes a given item maybe 2 to 8 times a month, and some items once a quarter. That is very little data, and it is intermittent and lumpy.

So the rule is: **below roughly 10 non-zero movements for a product, do not forecast.** Show the user's own par level and say the history is not there yet.

```
Henüz yeterli geçmiş yok.
Hedef miktarı sen belirle:  [__] adet
```

This is what the market does too, and it is worth knowing that the confident-sounding products gate hardest. Zoho's Zia requires order history before it predicts. Cin7 splits dumb thresholds from ForesightAI by product tier. Sortly does not forecast at all and only offers threshold alerts.

A wrong prediction shown confidently costs more trust than an honest "not yet". The feature's credibility is the product.

## Three tiers of certainty

| Data available | What we show | How |
|---|---|---|
| 0 to 1 movements | A par level the user sets | No computation |
| 2 to 9 movements | Par level, plus a simple average as context, labelled as rough | Mean of observed intervals |
| 10+ movements | Consumption rate, days of cover, reorder point | SBA |

Items cross tiers automatically as history accumulates. The user is not asked to do anything.

## The method

**SBA (Syntetos-Boylan Approximation)**, not plain Croston. Croston separates demand size from inter-demand interval and smooths each, but it over-forecasts by 5 to 18 percent depending on the smoothing constant. SBA corrects that bias with a `(1 - α/2)` factor and is the practitioner default for intermittent demand.

For items that may have gone obsolete, TSB decays toward zero instead of freezing a stale estimate, which matters for a product a cafe stopped using.

**No machine learning.** The M5 competition's ML advantage came from cross-learning across millions of SKU-store series and shrinks or reverses at the single-SKU level, which is the only level a single tenant has. Plain exponential smoothing outperformed the large majority of M5 entrants. Building an ML forecaster here would cost effort and lose accuracy.

Everything is computed in PHP. The model never does the arithmetic (D7).

## What the user actually sees

Three surfaces, in order of how often they are useful:

**1. Expiring soon.** The most immediately valuable output and the one requiring no forecast at all, just a date comparison over lots. What expires in the next N days, per location, sorted by urgency. A cafe uses this daily.

**2. Running low.** Items below their reorder point (forecast tier) or below their par level (par tier). Days of cover shown where it is known.

**3. Shopping list.** Generated from the two above, plus manual additions. Every line carries the reason it is there:

```
🥛 Süt              2 adet    2 gün içinde bitiyor
🌾 Un               1 çuval   hedef seviyenin altında
🧴 Deterjan         1 adet    sen ekledin
```

The reason column is not decoration. It is what makes a suggestion checkable, and a checkable suggestion is one the user can trust.

## Waste is a first-class output

Because `waste` is a distinct movement reason and never folded into `consumption` (see `data-model.md`), two numbers come free:

- **Waste percentage**: waste-reason outflow over total outflow.
- **Sell-through before expiry**: how much of a lot was consumed before its date.

For a cafe these are the numbers that pay for the subscription. They are v1 as raw figures; the reporting surface around them is v2.

## Error and empty states

- **No history at all.** Par level prompt, not a blank chart.
- **Insufficient history.** Say so explicitly. Never interpolate a confident number from three data points.
- **An item consumed once and never again.** TSB decays it rather than predicting a repeat. It should drop off the shopping list, not haunt it.
- **Expiry date unknown.** The lot simply does not appear in the expiring list. It is not guessed from a default shelf life unless the product defines one, and then it is labelled as estimated.
- **Seasonal item.** Out of scope for v1 with this little data. Do not pretend to detect seasonality from 12 observations.

## Quota effects

None for the computation. It runs on the tenant's own ledger.

Phrasing a shopping list into natural language through the assistant consumes a credit, but the list itself renders from a template for free.

## Acceptance criteria

1. A product with fewer than 10 movements never displays a forecast number, only a par level.
2. A product with 10+ movements displays consumption rate, days of cover and a reorder point, and the numbers reconcile with the ledger by hand.
3. Every shopping list line states why it is there.
4. The expiring list is correct against the lot data, verified by test with known dates.
5. Waste percentage is computed only from `waste`-reason movements.
6. An item not consumed for three intervals drops off the shopping list rather than persisting.
7. No forecasting code path calls a model.

## Open

- The exact threshold for switching from par level to SBA. Ten is a reasoned starting point, not a sourced constant; no citable minimum exists. Instrument it and tune.
- Whether weekly seasonality is worth detecting for cafes, which have real day-of-week patterns. Probably v2, and only with a season's worth of data.
- Lead time. A reorder point needs one, and we do not know the supplier lead time. Options: ask the user once per product, infer it from the gap between a shopping-list appearance and the next purchase movement, or default to a global value. Design should decide.
- How to express uncertainty visually. No good precedent was found for showing a probabilistic inventory forecast to a non-technical user, so this needs design invention rather than a copied pattern.
