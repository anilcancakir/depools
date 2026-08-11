# Depools.ai product documentation

The product definition for Depools.ai: an AI-assisted inventory app for small businesses and households, built as one Flutter app for iOS, Android and web on a Laravel API.

Written 2026-08-05 from nine research passes plus a full read of the abandoned MVP at `~/Code/depools` and `~/Code/depools-api`. Written for both a human reader and an LLM planning implementation.

## Read in this order

| Document | What it answers |
|---|---|
| [product.md](product.md) | Who it is for, what it does, what it deliberately does not do |
| [market.md](market.md) | Competitors with verified pricing, where the opening is, go to market |
| [open-decisions.md](open-decisions.md) | every decision with the reason behind it, and the questions still open with the assumption we proceed on. 70 and counting, so the file is append-only and a superseded decision is annotated in place rather than deleted (see D34, which D70 half-corrects) |
| [data-model.md](data-model.md) | The ledger, lots, tenancy, every table, 10 invariants |
| [architecture.md](architecture.md) | Repository shape, Flutter and Laravel layers, the gateway pattern |
| [ai-design.md](ai-design.md) | What the model does and does not do, gateways, approval, cost control |
| [monetization.md](monetization.md) | The meter, plan shape, behaviour at the limit, payment providers |
| [legal-and-privacy.md](legal-and-privacy.md) | GDPR obligations with KVKK as the local overlay, data source licensing, the scraping risk record |
| [iterations.md](iterations.md) | v1, v2, v3, and what is explicitly not planned |

## Features

One document per feature. Each carries the flow, error and empty states, quota effects, acceptance criteria, and what is still open.

These were written at summary depth on purpose, to be grown once the design mockups settled the interaction decisions. That has happened: every one now carries a **Screens** table (the surfaces it owns, their routes and the states each renders) and a **What the design settled** section naming the decisions the mockups produced. What remains under **Open** is genuinely open.

| Feature | |
|---|---|
| [inventory-core.md](features/inventory-core.md) | Products, locations, lots, the movement ledger |
| [stock-movements.md](features/stock-movements.md) | Taking stock out and putting it in: the two most frequent actions |
| [filtering-and-saved-views.md](features/filtering-and-saved-views.md) | The stock list's filter axes, saved filters, and the visibility rule |
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

## Where this stands

Done: `DESIGN.md` and the design mockups, which settled the interaction questions these documents left open; the feature documents grown to match, each with a Screens table and a "what the design settled" section; every screen routed inside the shell it will live in.

**The app is still fixture-driven.** 21 routes, 46 screen previews and 32 components render from 11 fixture files, with zero `Http` calls in `lib/`. The backend has 5 of roughly 20 tables and none of `app/Ai/`, `app/Mcp/`, or the Catalog, Capture, Forecasting and Placement services.

So what comes next is the fixture-to-API seam, feature by feature: `/ac:plan`, then `/ac:execute`, then `bin/check` and a dusk walk at both widths.
