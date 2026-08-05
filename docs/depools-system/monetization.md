# Monetization

How Depools.ai charges, what it meters, and how a limit behaves when it is reached.

The previous MVP metered five axes at once (users, products, locations, barcode scans, AI requests), rewrote its plan schema five times, and surfaced an exhausted quota as a dead-end 403 with no upgrade path. None of that repeats.

## The meter

Three dimensions, chosen because a user can predict each one:

**1. Unique SKU count.** How many distinct products the tenant tracks. Quantities do not count: holding 400 bottles of one water brand is one SKU. This mirrors Sortly's meter, including its explicit tooltip that quantities are excluded, because it is the one meter in this category users appear to understand.

**2. AI credits per month.** One credit per billable AI action. A receipt scan, a product photo analysis, an assistant message with tool use, a batch of generated tags. Credits exist because AI cost is real and varies by an order of magnitude between models, and because the alternative (unmetered AI on a flat tier) means a single heavy user can consume a month's margin.

**3. Movement history retention window.** How far back the ledger stays queryable: one month, one year, three years, unlimited. Sortly proves the market accepts history depth as a tier lever, and our ledger provides it at no extra engineering cost.

### What is never metered

- **Seats.** Unlimited on every tier including free. Charging per seat in a business with three people caps revenue at nothing while actively discouraging the shop assistant from using the product, which is the adoption we most want.
- **Locations.** The location hierarchy is how the product delivers value. Limiting it makes the product worse at the thing it is for.
- **Stock movements.** Metering the ledger would mean a user hits a wall mid-month and cannot record what they just did. Sortly meters retention, not write volume, and that is the right instinct.
- **Barcode scans.** The MVP metered these separately and it produced the dead-end error described above. Scanning that resolves from our own catalog costs us nothing; only the external lookup has marginal cost, and that is already covered by the AI credit and catalog logic.

## Plan shape

Concrete numbers are open (see O6 in `open-decisions.md`) and must be validated against Turkish willingness to pay before launch. The shape is settled:

| Tier | Unique SKUs | AI credits/month | History retention | Audience |
|---|---|---|---|---|
| Free | ~100 | small monthly allowance | 1 month | Households, and businesses evaluating |
| Starter | ~500 | moderate | 1 year | A cafe or single shop |
| Growth | ~2,500 | generous | 3 years | Multi-location or higher SKU count |
| Business | unlimited | high, with top-ups | unlimited | Established operations |

Every tier includes: all three capture paths, the full ledger with lots and expiry, location suggestion at all three automation levels, label printing, MCP read access, and both interface modes. Features are not withheld to force upgrades. The tiers differ in volume, not capability.

MCP access is rate-limited per tier rather than paywalled. Of nine vendor MCP servers surveyed, only Notion hard-gates by plan while Atlassian scales rate limits and seven others ship it free with the existing subscription. Rate limiting also has the useful property that heavy use pushes a tenant up a tier naturally.

## Behaviour at the limit

This is where the MVP failed, so it is specified rather than left to implementation.

**SKU limit reached.** The tenant keeps full access to everything already recorded. Nothing is hidden, nothing is deleted, the ledger keeps working, existing products keep receiving movements. Only creating a *new* product is blocked, and that block surfaces as an in-context upgrade prompt showing the current count, the tier limit, and what the next tier costs.

**AI credits exhausted.** Every AI-assisted path degrades to its manual equivalent rather than erroring. A receipt photo still creates a receipt record the user can key in by hand. Barcode scanning still resolves against our own catalog and the community catalog, because those cost nothing. Only the external lookup and the model calls stop. The assistant still answers from computed data, it just cannot call a vision model. The user sees what ran out and when it resets.

**Retention window exceeded.** Older movements are not deleted, they become unqueryable in the UI and in reports. Upgrading restores access to history that was accumulating the whole time. Deleting a user's history because they are on a cheap tier would be hostile and would break the forecasting the product promises.

**No active subscription.** A tenant always has a subscription row. On team creation they get the free plan with an end date of null. The MVP's `SubscriptionUsageService` dereferenced `activeSubscription` without a null guard, which is only safe if that invariant is enforced, so it is enforced here explicitly and tested.

## Payment providers

Three paths, because no single provider covers our market (see O1 in `open-decisions.md`):

- **Turkish web checkout**: a local provider, iyzico or PayTR. Stripe is limited for Turkish legal entities.
- **International web checkout**: Stripe.
- **Mobile**: App Store and Play Store in-app purchase where platform rules require it, which for a subscription unlocking app functionality they generally do.

The `payments` and `plan_prices` tables model provider per row, so a plan carries a different price and product identifier per provider and platform. The MVP already had this shape and it was the right call.

### Webhooks are mandatory, not optional

The MVP wrote a `StripePaymentService::webhook()` method and never routed it. Verification happened only when the user returned to the app with a `session_id` query parameter. The consequence: renewals, cancellations, failed payments, expired cards and chargebacks never reached the system, and subscriptions died silently when `ends_at` passed.

For v1, every provider's webhook is routed, signature-verified, idempotent by event id, and covered by a test that replays a real payload. Specifically handled: subscription created, renewed, payment failed, subscription cancelled, refund issued, and for store IAP the equivalent server notifications.

## Trials

The MVP allowed one trial per team, forever, on one plan only, keyed on `trial_ends_at IS NOT NULL`. A team that trialled Starter in 2025 could never trial anything again.

For v1: a trial is available once per team, applies to any paid tier, and the eligibility check is explicit rather than inferred from a nullable timestamp. Whether a trial requires a payment method is an open commercial question, not an architectural one.

## Cost accounting

`ai_usage_events` records one row per billable AI action with the model used, input and output token counts, and computed cost in USD. This exists so three questions have answers: what does this tenant cost us, is the credit price above our marginal cost, and which feature is consuming the budget.

The MVP stored token counts on conversation rows and never aggregated them, so none of those questions could be answered. The Filament panel (D19) surfaces this per tenant.

Additionally: the icon suggestion endpoint in the MVP called a model outside the quota system entirely, so a free user could consume unlimited model calls through it. Every model call in v1 goes through a gateway that records usage and checks the credit balance. No exceptions, enforced by the gateway interface rather than by remembering.

## Known pricing hazards

Recorded because the MVP hit two of them:

1. **Currency entry errors.** The MVP's seed data set Starter's TRY web price to 9.99 against Plus at 399.99, an obvious data-entry mistake that would have sold a subscription for roughly a quarter of a dollar. Prices need a validation rule that rejects a value implausibly far from the tier's other currencies.
2. **Repeated schema churn.** The plan schema was rewritten five times in three months because the metering model was never settled. It is settled here first, which is the point of writing this document before the code.
