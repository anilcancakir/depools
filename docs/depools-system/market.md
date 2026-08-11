# Market and positioning

Evidence behind the positioning fixed in `product.md`. Every figure carries a source. Figures that could not be verified against a primary source are marked UNVERIFIED and must not be quoted as fact.

Researched 2026-08-05. Pricing in this category moves, so re-check before using any number in external material.

## Bottom line

The household side of AI inventory is crowded and price-capped. The business side has no agentic assistant and no expiry tracking. That intersection is the opening.

## Household competitors

Nine or more products shipped photo-to-item AI or AI chat during 2025 and 2026, several launched after the January 2025 Palisades fire drove demand for insurance documentation.

| Product | Pricing | AI features | Notes |
|---|---|---|---|
| [Kept](https://getkeptapp.com/) | Free 50 items, kept+ 19.99 USD/year | AI Capture (photo to item), "ask kept" chat over your own items, CPSC and FDA recall monitoring free forever | Verified by reading the site. Positioning is literally "the free home inventory app you can talk to". Ships as a PWA, no App Store, no account required. Free tier includes 5 AI chat questions and 3 AI Captures |
| [HomeZada](https://www.homezada.com/homeowners/pricing) | Free tier, Premium 99 USD/year or 15.95 USD/month, Deluxe 189 USD/year | AI chat and photo credits metered at every tier, 300 extra credits for 25 USD | The clearest precedent for AI-credit metering |
| [Memento Database](https://mementodatabase.com/pricing.html) | Free, Pro 8 USD/month, Business 14 USD/user/month | AI assistant, credit-metered (200 free, 2,000 Pro) | Strongest traction in the cohort: 4.43 rating over 26K Play ratings, 1M+ downloads |
| Manifest, Bevel, MovingBox, Vorby, Scanlily, ShelfLily | Free tiers common, Pro pricing varies | Photo, video or receipt to inventory | All AI-native 2025-2026 entrants. Individual claims not independently verified |
| [Dib](https://dib.io/) | Reported 120 USD/year, UNVERIFIED | Reported "chat with your home" | Site returns HTTP 451, blocked from Turkey under US export and OFAC rules, so it could not be verified FROM HERE. Under D116 it is a competitor in the primary market and the verification is still owed; the earlier note that it is not a competitor was reasoning from the old market order |
| [Encircle](https://www.getencircle.com/) | Quote-based, roughly 270 to 650 USD/month | None found | B2B restoration and insurance adjusting, not a consumer product |

Read this as: photo-to-item recognition and chat-over-your-items are table stakes on the household side, not differentiators, and the price ceiling is roughly 20 USD per year.

## Business competitors

| Product | Entry price | Limits at entry | AI in 2026 |
|---|---|---|---|
| [Sortly](https://www.sortly.com/pricing/) | Free, then Advanced 49 USD/month listed and 24 USD promotional | Free: 100 unique items, 1 user, 2 jobs. Advanced: 500 items, 2 users | None. Verified: the full feature matrix contains zero AI rows |
| [Zoho Inventory](https://www.zoho.com/inventory/pricing/) | Free, Standard 29 USD/month | Free: 50 orders/month, 1 user, 2 locations | Zia demand forecasting and contextual chat, gated on order history |
| [inFlow](https://www.inflowinventory.com/software-pricing-inflow) | 161 USD/month annual | 100 orders/month, 2 users, 1 location | AI reorder recommendations |
| [Katana](https://katanamrp.com/pricing/) | Free 30 SKUs, Core 299 USD/month | Core: unlimited SKUs, 1 location | AI Replenishment as a paid add-on, not included |
| [Cin7 Core](https://www.cin7.com/) | Standard 349 USD/month | 5 users, 6,000 annual orders | ForesightAI: 24-month demand forecast and smart reorder points |
| Shopify native | Free with any plan | Variant limit raised to 2,048 in Winter 2026 | No native forecasting. Shopify is sunsetting its own forecasting app Stocky on 2026-08-31, leaving small sellers without a first-party reorder tool |

## What Sortly actually monetises, and why it matters

Reading Sortly's own pricing-page feature matrix directly produced the most useful finding in this research. Their paid tiers are carried by the movement history our MVP did not have:

| Feature | Free | Advanced | Ultra | Premium |
|---|---|---|---|---|
| Activity history retention | 1 month | 1 year | 3 years | Unlimited |
| Transaction reports | 1 month | 1 year | 3 years | Unlimited |
| Item Flow and Move Summary reports | no | yes | yes | yes |
| Check-in / check-out | no | no | yes | yes |
| Offline mobile access | no | yes | yes | yes |
| Low stock and date-based alerts | no | yes | yes | yes |

Three conclusions:

1. The ledger is not only an architectural necessity, it is a proven pricing axis. Retention window is a tier lever the market already accepts.
2. Sortly's meter is "unique items" and its own tooltip states that quantities of an item do not count toward the limit. That is a user-comprehensible meter and worth copying.
3. Their "date-based alerts" are for maintenance and repair schedules, not expiry, and there is no lot tracking anywhere in the matrix. Perishables are genuinely unserved by the category leader.

## The dual-audience question

Sortly is the only real precedent for serving both households and businesses, and its reviews show the strain. Home users with large static collections are billed on the same unique-item meter as businesses with high transaction churn but fewer SKUs. Actual review language from [Capterra](https://www.capterra.com/p/169199/Sortly-Pro/reviews/):

- "highway robbery for consumers who only use their system for managing a home inventory for insurance purposes" (Ron C., 1 star, 2025-02-24)
- "Since the price increase, the cost doesn't make sense, and we will migrate to another app" (Sirena M., 2025-04-22)
- "300% price increase with only 30 days supposed notice" (Steve S., 2 stars, 2025-05-07)

The lesson is specific: dual audience works as a product surface and fails as a single pricing meter. Our answer is the free tier for households plus a meter (unique SKUs, AI credits, retention) that a household naturally sits under rather than one that punishes them for owning things.

## Pricing patterns worth copying

Three structures, each drawn from a real competitor:

1. **Unique-item ladder** (Sortly): free at 100 items, paid tiers at 500, 2,000 and 5,000, quantities excluded from the count.
2. **AI-credit overlay** (HomeZada, Memento): the tier price stays feature-based, and every tier carries a monthly AI action allowance with paid top-ups. This is how we gate vision and assistant cost without re-metering the whole product.
3. **Retention window** (Sortly): history depth as a tier lever, which our ledger provides for free.

Zoho prices near 1:1 between USD and EUR, so EUR needs no separate discount. Annual discounts in the category cluster between 15 and 50 percent.

## Market size

2026 estimates for inventory management software range from 2.7B to 4.5B USD with CAGR between 8.4 and 13.1 percent depending on the research firm ([Grand View](https://www.grandviewresearch.com/industry-analysis/inventory-management-software-report), [FnF Research](https://www.fnfresearch.com/global-inventory-management-software-market-by-product-advanced)). No source isolates an SMB-only or consumer-only segment. Treat as directional context, not a sizing input.

Traction in the household cohort is modest across the board: the strongest is Memento Database at 1M+ downloads, Sortly holds 4.7 over 9.4K App Store ratings, HomeZada's mobile app has 2.9 over 44 ratings. This is a fragmented, low-moat market rather than a winner-take-all one.

## Go to market

- **App store search**: the head term "inventory" is high difficulty with 250+ competing apps. Long-tail terms ("inventory management", "inventory manager", "inventory control") sit at far lower difficulty and are the realistic entry point ([ASOTools](https://asotools.io/app-store-keywords/inventory)).
- **Content**: the household space is saturated with "best home inventory app" listicles that themselves function as the discovery layer, ranking above the apps' own sites. The realistic play is being listed favourably rather than outranking them.
- **Turkish channels**: no Turkish product was found doing consumption forecasting for a household or small business, and the Turkish stock-tracking tools that exist (Jet Stok, BirFatura, Tezgah) integrate at the marketplace-API or e-invoice-integrator level. This is an unserved local segment with no incumbent to displace. Under D116 it is a second market rather than the first, so read this as a channel that stays available and cheap to enter, not as the entry point.
- **Reddit and community**: could not be verified in this research pass. Repeated `site:reddit.com` queries returned unrelated results. If community sentiment becomes load-bearing for copy, it needs a dedicated pass with direct Reddit access.

## Trust as a differentiator

No competitor surveyed publishes an explicit "we do not train on your photos or data" commitment. For a product holding photographs of people's homes and business stock, saying it plainly is cheap and currently unclaimed.

Self-hosting exists as a niche selling point ([HomeBox](https://homebox.software/en/) markets "no cloud sync, no third-party access, no telemetry") and no mainstream competitor offers it. Not a v1 concern, but worth knowing the position is open.

GDPR obligations, with KVKK as the local overlay, are covered in `legal-and-privacy.md`. They are a compliance surface, not a marketing feature, with one exception: KVKK's separate-consent requirement is the strictest of the two and forces a clearer disclosure than most competitors offer, so building for it produces a clarity that can be presented as a strength rather than a legal chore. That holds in the primary market too, where nobody is asking for it.
