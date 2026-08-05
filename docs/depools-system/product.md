# Depools.ai: product definition

Depools.ai is an AI-assisted inventory app for small businesses and households. A user photographs a receipt, scans a barcode, or types "1 adet süt aldım", and the item lands in stock with the right quantity, the right unit, the right location and the right expiry date. From then on the app knows what is running low, what is about to expire, and what to buy next.

This document defines who it is for, what it competes against, and what it deliberately does not do. Every other document in `docs/depools-system/` assumes the positioning fixed here.

## The one-sentence positioning

For a small business owner who is not a systems person, Depools.ai turns the things you buy into a stock record that maintains itself, and tells you what to reorder before you run out.

## Primary audience

Small businesses of 1 to 10 people that hold physical stock and currently track it in a notebook, a spreadsheet, or their head:

- Cafes and small restaurants: perishable goods, daily consumption, waste that nobody measures.
- Small retail and neighbourhood shops: a few hundred SKUs, barcodes on most items, price labels to print.
- Workshops and repair shops: parts and consumables in labelled bins, no barcodes on half of it.
- E-commerce sellers with their own storage: a few hundred SKUs, multiple storage spots.

Households are a real secondary audience, served by the same product on the free tier. A household is not a different product, it is a small business with one member, no SKUs and no labels.

### Why business first

The evidence is in `market.md`. Three points decide it:

1. Household AI inventory is already crowded and price-capped. Kept ships photo-to-item capture, chat over your own items and recall alerts for 19.99 USD per year. Competing there on AI features means competing against free.
2. Business entry pricing is 10 to 25 times higher for the same category of software, and the buyer has a budget line for it.
3. The previous MVP's own feature set was already business-shaped: teams with roles, SKUs, kilogram and litre units, barcode label design, batch label printing. No household prints barcode labels for a pantry. The code had already picked the audience.

## The wedge: perishables and simplicity

Two gaps in the market, both verified:

**Nobody tracks expiry properly.** Sortly's own feature matrix has no expiry or lot tracking; its "Date-based Alerts" are for maintenance and repair schedules. Kept holds no quantities at all. The AI-native household entrants recognise items from photos but do not model stock. Meanwhile a cafe throws away milk every week and cannot say how much.

**Nobody is simple enough.** Every business inventory product assumes an operator who understands SKUs, reorder points and stock takes. Our user does not, and should not have to.

Expiry plus simplicity is what lets one product serve a cafe and a household honestly. Both need to know what they have, where it is, and what is about to go bad. Neither wants to learn inventory management.

## What the product does

Ordered by how central each is to the promise.

1. **Capture.** Get a thing into stock with as little effort as possible. Receipt photo, barcode scan, product photo, natural language, or a normal form. See `features/receipt-ingestion.md`, `features/barcode-and-catalog.md`, `features/ai-enrichment.md`.
2. **Locate.** Know where it is, in a hierarchy the user names themselves (building, room, shelf, box). Suggest the right location automatically, from what already lives there. See `features/location-assignment.md`.
3. **Track.** Every change to stock is an event with a reason, an actor and a timestamp, and stock that expires is tracked per lot. See `features/inventory-core.md`.
4. **Anticipate.** Consumption rate, days of cover, what expires this week, what to buy. See `features/forecasting.md`.
5. **Act.** An assistant that can do the work, not just answer questions about it, with an approval gate on anything that changes stock. See `features/ai-assistant.md`.
6. **Label.** Print barcode labels for items that have none, so they can be scanned later. See `features/labeling-and-printing.md`.
7. **Open up.** Expose the user's own inventory to the user's own AI assistant over MCP. See `features/mcp-server.md`.

## Two ways to use it, chosen by the user

The research on conversational interfaces is consistent and worth stating plainly: chat is an excellent capture surface and a poor system of record. Users cannot get an overview from a transcript, cannot bulk-edit in a text box, and abandon after two or three clarifying questions.

So the app ships both surfaces and lets the user pick which one is the front door:

- **Assistant mode.** The assistant is the home screen. You talk or photograph, it acts, and it shows you a compact card to fill in the rest. Conventional screens are still there, one tap away.
- **Inventory mode.** A conventional stock list is the home screen, with search, filters and bulk edit. The assistant is available as a sidekick, not a wall.

This is a user preference, changeable at any time, not an onboarding fork that locks them in. Both modes read and write the same data through the same rules. Neither mode is a degraded version of the other.

Platform split follows naturally: mobile is where capture happens (camera, scanner, voice), web is where review happens (bulk edit, reports, label sheets, billing).

## What the product does not do

Stating these keeps scope honest and stops feature requests from becoming architecture:

- **It is not an accounting product.** It does not produce ledgers for a tax office, compute VAT returns, or replace a Turkish ön muhasebe tool. It reads invoices to learn what was bought, and stops there.
- **It is not a point of sale.** It does not take payments or run a till. It can decrement stock when told, but it does not sit between the shop and the customer.
- **It is not a warehouse management system.** No wave picking, no slotting optimisation, no barcode-driven pick paths, no multi-warehouse transfer orders.
- **It is not a supplier marketplace.** It can tell you to buy more flour. It does not sell you flour.
- **It does not promise offline-first.** Capture must degrade gracefully when the network drops, but the app is online software.

## How we will know it works

Product-level success criteria, in the order they matter:

1. A new user gets their first 10 items into stock in under 5 minutes, without reading anything.
2. A receipt photo of a normal Turkish grocery run produces line items the user accepts with edits to fewer than 3 lines.
3. A week after signup, the user has come back and recorded a stock movement they were not prompted to record.
4. The expiry list is correct often enough that the user acts on it rather than checking the shelf.
5. A location suggestion is accepted without change more than half the time, once the user has 20 items.

Numbers 3 and 5 are the real ones. The first two measure onboarding; the last three measure whether the product became part of how the business runs.

## Reference documents

- `market.md`: competitors, pricing, positioning evidence, go to market.
- `data-model.md`: the ledger, lots, tenancy, the full schema.
- `ai-design.md`: agents, tools, approval gates, model choice, cost model.
- `monetization.md`: plans, meters, quota enforcement, payment providers.
- `architecture.md`: Flutter and Laravel layers, the fluttersdk packages, gateway interfaces.
- `legal-and-privacy.md`: KVKK and GDPR obligations, data source licensing, the scraping risk record.
- `iterations.md`: what is in v1, what waits for v2.
- `open-decisions.md`: decisions taken with their reasons, and questions still open.
- `features/`: one document per feature, each with its input and output contract, flow, error states, quota effects and acceptance criteria.
