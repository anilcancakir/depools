# Iterations

What ships in v1, what waits, and why each line is where it is. A feature is in v1 only if the product is incoherent without it.

The v1 test: a cafe owner who has never used inventory software can get their stock in, keep it current, and be told what to buy before they run out.

## v1

### Foundation

- Fork from `magic_example`, six-step rename procedure, hosted pubspec constraints.
- `DESIGN.md` plus `design:sync`, token allowlist, `bin/design-tokens` enforcement, `bin/check` gate.
- iOS, Android and web targets only. Mobile-first layouts.
- Identity, teams, roles, invitations, 2FA, sessions, notifications: configured from `magic_starter`, zero bespoke code (D21).
- Turkish and English, complete. The MVP shipped 25 percent Turkish coverage and that will not repeat.

### Inventory core

- Products with a base unit, package unit conversions, optional SKU and expiry tracking.
- Location hierarchy with materialised path, depth cap and cycle guard.
- Append-only movement ledger with the full reason and source vocabulary.
- Lot-level expiry, FEFO consumption, `waste` as a distinct reason.
- Derived stock per product and location, with a consistency check against the ledger.
- Search and filtering on Meilisearch, covering products, locations, categories and the global catalog. One search destination (`/search`) returning results grouped by kind, with filtering staying on the list it narrows.

### Capture

- Manual entry. One home screen (the overview); the user's preference selects the pinned capture verb rather than a separate front door (D66).
- Barcode scanning on all three platforms via `mobile_scanner`, with the three-stage resolution cascade: own products, community catalog, external lookup.
- Receipt photo to line items, with a mandatory per-line confirmation screen.
- Structured e-Fatura and e-Arşiv XML ingestion (UBL-TR 1.2.1) for business supplier purchases.
- Forward-to-address email ingestion with a unique inbound address per tenant.
- Product photo to product card.
- Natural language capture, act-first on parsed facts, one grouped follow-up card.
- Push-to-talk voice input feeding the same pipeline.

### Intelligence

- Automatic location suggestion from co-location affinity, with the manual, semi-auto and full-auto dial.
- Expiry list: what expires in the next N days, per location.
- Par-level tracking for items with insufficient history.
- Guided stock take producing `stock_take` corrections. Moved up from v2: the ledger carries the reason from day one, so the screen was the only missing part, and a cafe that cannot reconcile a count against the record stops trusting the record.
- SBA forecasting, consumption rate and days of cover for items with enough history.
- Generated shopping list with the reason attached to each line.
- Assistant with read tools plus write tools behind an approval gate, streaming responses, image input, and web search.
- A persistent assistant affordance on every screen, dismissable from settings (D67), opening as a
  full-screen overlay above the current screen rather than pushing a route (D69). The AI is the
  layer the product is operated through, so it is not confined to one route, and asking it about
  the thing in front of you must not cost you the thing in front of you.

### Labels

- A4 multi-label sheets rendered on the BACKEND from one Blade template through `spatie/browsershot`,
  producing the PDF that prints and the PNG that previews (D18 reversed, D71). One engine everywhere;
  what differs per environment is the Chrome binary path, not the renderer.
- Fonts embedded in the template as base64, asserted by a test, because `Ğ ğ İ Ş ş` failing looks like
  a fallback glitch rather than a missing glyph and on a label it is printed onto adhesive paper.
- Label size and page catalog ported from the MVP's `config/labels.php`, which is genuinely reusable.
- One screen with three sections, not a wizard (D42). No sequential gate, so every decision is
  reachable at every moment and there is no step to be stuck on.

### MCP

- Read-only server over Streamable HTTP, OAuth 2.1 with Passport, tenant-scoped resource URI.
- Five tools: search items, get item, list stock by location, list expiring items, list locations.
- Tenant isolation test suite written before the wiring.

### Commerce and operations

- Plans metered on unique SKU count, AI credits and history retention window. Unlimited seats.
- Turkish payment provider for TRY, Stripe for international, store IAP where the platform requires it.
- `ai_usage_events` with token counts and computed cost per tenant.
- Filament panel scoped to users, teams, subscriptions, basic statistics, inventory and location inspection, and audit log.
- Single minimum-version check endpoint. No announcement or changelog system.

### Legal

- Separate aydınlatma and açık rıza documents, consent recorded per purpose with version and timestamp.
- Redaction step before any content reaches a model.
- Data export and account deletion.

## v2

Ordered by expected value, not by ease.

- **MCP write tools.** `preview=true` by default, idempotency key on apply, shared pending-change service with the in-app assistant.
- **Gmail and Outlook OAuth ingestion** as a power-user upgrade, once there is a CASA budget line and counsel has signed the cross-border language.
- **Bluetooth thermal label printing.** TSPL first, because it is officially documented and is what the cheap Xprinter and TSC clones sold in Turkey actually speak. Niimbot second, ported from MIT-licensed reference implementations, Android-only until a BLE-exposing unit is confirmed.
- **Hands-free voice**, wake word plus streaming transcription, with real foreground-service plumbing.
- **Supplier and purchase orders.** Once the shopping list is trusted, the next step is sending it somewhere.
- **Waste and cost reporting.** Waste percentage, sell-through before expiry, cost of spoilage. The ledger already carries the data from day one.
- **Multi-location transfer workflow** beyond the simple paired movement.
- **Announcement and changelog system**, if in-app communication becomes a real need.

## v3 and beyond

Candidates, not commitments:

- On-device vision for offline capture. Blocked today: the models exist but no production-ready Flutter binding does, and the deployment tooling is native rather than plugin-level.
- Recipe or bill-of-materials consumption, so a cafe decrements ingredients when it sells a drink. This is where the product would start becoming an MRP, and that boundary needs a deliberate decision.
- Community catalog as a public good, with an open licence and an API.
- Migration to the 2026-07-28 MCP revision once `laravel/mcp` supports it.

## Explicitly not planned

Recorded so they are not re-proposed:

- Point of sale, payment acceptance, till operation.
- Accounting, VAT returns, ön muhasebe replacement.
- Warehouse management: wave picking, slotting optimisation, pick paths.
- Supplier marketplace or procurement brokerage.
- Offline-first architecture. Capture degrades gracefully, but this is online software.
- Desktop platform targets.
