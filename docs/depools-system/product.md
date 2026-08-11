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

## One home, and the AI is the layer rather than a mode

The research on conversational interfaces is consistent and worth stating plainly: chat is an
excellent capture surface and a poor system of record. Users cannot get an overview from a
transcript, cannot bulk-edit in a text box, and abandon after two or three clarifying questions.

An earlier version of this document drew the wrong conclusion from that. It offered two front
doors, an assistant mode and an inventory mode, chosen by the user. The 2026 literature is
unusually united against that shape: "they pick one pattern and commit, no hybrids" (Design Key,
2026-05), "the products winning in 2026 put the AI behind a verb, a canvas, a delegation or an
ambient capture rather than behind a prompt" (Adaline, 2026-06), and conversation is for
meaning-making while direct manipulation is for doing (The Conversation Trap, 2026-03). Two front
doors is a hybrid, it doubles the surface to maintain, and it makes a blank text box the first
thing a whole class of users sees. The same literature names a hidden literacy tax on that: people
who are fluent communicators still struggle to write effective prompts, and our user is precisely
the person who should never have to learn.

So there is ONE home screen, the overview, and it answers "what needs my attention". Four counters,
the capture actions, and the four surfaces that carry work: dates, running low, the shopping list
and recent movements.

**What the user chooses is the first capture verb, not the front door.** The preference decides
which surface is pinned at the top of the overview: the assistant composer, for someone who
describes what happened, or search plus the stock list, for someone who looks things up. One home,
one pattern, and the choice is still the user's. Changeable at any time, and neither option is a
degraded version of the other.

**The AI is the foundation, not a feature on it.** Stock movements, adding a product, scanning a
barcode: every capability in this product is reachable through the assistant, and that is a
positioning decision rather than a convenience. So the assistant has a persistent affordance on
every screen rather than living behind one route. A user who wants the conventional path never has
to use it, and can turn it off in settings, which is the concession the research above earns: the
assistant is always within reach and never in the way.

There is no platform split. iOS, Android and web are one Flutter app with one feature set:
everything a user can do on a phone they can do in a browser, and the design is the same in both.
Capture (camera, scanner, voice) and review (bulk edit, reports, label sheets, billing) are all
present everywhere, laid out for the WIDTH they are given rather than for the platform they run on.

What differs is only what the hardware makes convenient. A phone in a shop is where a receipt photo
usually gets taken because the camera is in your hand; a wide window is where a bulk edit usually
happens because the rows fit. Neither is enforced, and neither screen is missing on the other
platform.

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
- `legal-and-privacy.md`: GDPR obligations with KVKK as the local overlay, data source licensing, the scraping risk record.
- `iterations.md`: what is in v1, what waits for v2.
- `open-decisions.md`: decisions taken with their reasons, and questions still open.
- `features/`: one document per feature, each with its input and output contract, flow, error states, quota effects and acceptance criteria.
