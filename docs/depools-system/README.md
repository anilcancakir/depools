# Depools.ai product documentation

The product definition for Depools.ai: an AI-assisted inventory app for small businesses and households, built as one Flutter app for iOS, Android and web on a Laravel API.

Written 2026-08-05 from nine research passes plus a full read of the abandoned MVP at `~/Code/depools` and `~/Code/depools-api`. Written for both a human reader and an LLM planning implementation.

## Read in this order

| Document | What it answers |
|---|---|
| [product.md](product.md) | Who it is for, what it does, what it deliberately does not do |
| [market.md](market.md) | Competitors with verified pricing, where the opening is, go to market |
| [open-decisions.md](open-decisions.md) | 21 decisions with their reasons, 7 questions still open with the assumption we proceed on |
| [data-model.md](data-model.md) | The ledger, lots, tenancy, every table, 7 invariants |
| [architecture.md](architecture.md) | Repository shape, Flutter and Laravel layers, the gateway pattern |
| [ai-design.md](ai-design.md) | What the model does and does not do, gateways, approval, cost control |
| [monetization.md](monetization.md) | The meter, plan shape, behaviour at the limit, payment providers |
| [legal-and-privacy.md](legal-and-privacy.md) | KVKK and GDPR obligations, data source licensing, the scraping risk record |
| [iterations.md](iterations.md) | v1, v2, v3, and what is explicitly not planned |

## Features

One document per feature. Each carries the flow, error and empty states, quota effects, acceptance criteria, and what is still open.

These are at **summary depth on purpose**. Design mockups come next, and the interaction decisions that come out of them are what these documents will be grown with. Writing full specifications before the design exists would mean writing detail twice.

| Feature | |
|---|---|
| [inventory-core.md](features/inventory-core.md) | Products, locations, lots, the movement ledger |
| [receipt-ingestion.md](features/receipt-ingestion.md) | Receipt photo and e-Fatura XML to stock |
| [barcode-and-catalog.md](features/barcode-and-catalog.md) | Scanning, the resolution cascade, the community catalog |
| [ai-enrichment.md](features/ai-enrichment.md) | Photo, name or barcode to a product card |
| [ai-assistant.md](features/ai-assistant.md) | The conversational surface, act-first capture, write tools |
| [location-assignment.md](features/location-assignment.md) | Automatic placement from co-location affinity, the automation dial |
| [forecasting.md](features/forecasting.md) | Consumption, expiry, the predictive shopping list |
| [labeling-and-printing.md](features/labeling-and-printing.md) | A4 label sheets, and why thermal printing waits |
| [mcp-server.md](features/mcp-server.md) | Exposing inventory to the user's own AI assistant |

## Conventions used here

- **Verified claims name their source.** Anything that could not be confirmed against a primary source is marked UNVERIFIED and must not be quoted as fact. Several pricing and accuracy figures fall into that category on purpose.
- **The MVP is cited as a counterexample** where it got something wrong, with the file and line, so the same mistake is not repeated by someone assuming it was intentional.
- **Decisions carry their reason.** A decision without a reason gets relitigated in three months.
- **Open questions carry an assumption.** So an unanswered question still leaves a recorded default rather than a fresh guess at implementation time.

## What comes next

1. `DESIGN.md` and the design mockups. This is the next task and it will settle the interaction questions the feature documents leave open.
2. Grow the feature documents with those decisions.
3. `/ac:plan` per feature, then `/ac:execute`.
