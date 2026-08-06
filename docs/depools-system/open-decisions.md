# Decisions and open questions

Two lists. The first records decisions already taken, each with the reason and the evidence, so they are not relitigated. The second records what is still open, with the assumption we proceed on until it is answered.

Decisions were taken on 2026-08-05 from nine research passes plus a full read of the abandoned MVP. Where a claim was verified against a primary source, the source is named. Where it was not, it says so.

## Taken

### D1. Business first, household on the free tier

Small retail, workshops, cafes, small e-commerce. Households use the same product, not a different one.

Why: household AI inventory is crowded and price-capped (Kept ships photo capture, AI chat and recall alerts at 19.99 USD/year), business entry pricing is 10 to 25 times higher, and the MVP's own feature set was already business-shaped.

### D2. Perishables are the go-to-market wedge, NOT the product's scope

Verified against Sortly's own pricing-page feature matrix: no expiry tracking, no lot tracking, and its "Date-based Alerts" are maintenance schedules. Kept holds no quantities. The gap is real, and it is what makes the first message land.

**Corrected 2026-08-06.** An earlier reading of this decision let the product itself become food-shaped, and it showed in code: the attention section tested expiry and zero stock only, so a workshop tracking spare parts or a shop tracking chargers saw an empty attention list however low they ran. Expiry is **one signal among several**, not the organising one.

The product serves any sector that holds stock: electronics, spare parts, consumables, tools, materials. A product with no expiry date is a normal product, not a degraded one, and every screen has to be reviewed against at least one of them. The wedge is how we get attention; it is not what the system knows how to hold.

### D3. Append-only movement ledger, derived balance, lot-level expiry

See `data-model.md`. Without a ledger, consumption rate, stockout prediction, waste measurement and audit are all impossible, and expiry cannot be modelled at all because expiry is a property of a lot.

Also a pricing axis: Sortly meters history retention (1 month free, unlimited on Premium).

### D4. Meter on unique SKU count, AI credits and history retention. Seats unlimited

The MVP metered five axes simultaneously (users, products, locations, barcode scans, AI requests) and users could not tell which limit they hit; it surfaced as a dead-end 403. Unlimited seats so team adoption is never penalised.

### D5. Turkey first, architecture ready for global, multi-currency from day one

The Turkish product-data gap is a moat that compounds with our own users' contributions, and Turkish e-Arşiv/e-Fatura integration is something no global competitor will build.

Cost: Stripe is limited for Turkish legal entities, so a local provider (iyzico or PayTR) is needed. Turkish price sensitivity caps ARPU.

### D6. `laravel/ai`, latest version pinned exactly, behind our own gateway interfaces

Chosen over `neuron-ai`. Its source tree ships `Approvals` (human-in-the-loop for write tools), `Store` and `Storage` (conversation persistence the MVP hand-rolled), `Streaming` (absent from the MVP), plus `Embeddings` and `Reranking`. Those are precisely the MVP's gaps.

Verified: `laravel/ai` has no Prism dependency, contrary to widely repeated blog claims. Its `composer.json` requires only `illuminate/*`, `aws/aws-sdk-php`, `laravel/prompts` and `laravel/serializable-closure`. `prism-php/prism` has not been pushed since 2026-03-20.

Cost: it is a v0.x package on a roughly monthly minor cadence, and minors can break. Hence the exact pin plus gateway isolation, following the pattern already used in the sibling `uptizm` backend.

### D7. Deterministic code computes every number. The LLM only explains

Consumption rate, days of cover, reorder point, waste percentage: all computed in code. The LLM turns the result into a sentence, handles ambiguous input, and produces suggestion explanations. It never does arithmetic over rows.

Why: frontier models degrade from high accuracy on simple lookups toward zero on multivariate tabular calculation.

### D8. Do not forecast below roughly 10 non-zero movements

Show the user-set par level and say the history is not there yet. Switch to SBA (Syntetos-Boylan) automatically once an item has enough history. Plain Croston over-forecasts by 5 to 18 percent, which is why SBA and not Croston.

No ML forecaster. The M5 competition's ML advantage came from cross-learning over millions of series and shrinks or reverses at single-SKU level, which is the only level a single tenant has.

Precedent for gating on data volume rather than showing a low-confidence guess: Zoho's Zia requires order history before it will predict; Cin7 splits dumb thresholds from ForesightAI by product tier.

### D9. Location suggestion ranks co-location affinity first, name semantics second

The signal is what already sits in a location, not what it is called. A drawer holding rice and bulgur should attract pasta even when it is named "Çekmece 2".

A per-tenant count table over (category, location) is the whole model: no training, updates instantly on correction, and the count is the explanation ("bu çekmecede zaten bulgur ve pirinç var"). Location name matching is the fallback for empty or new locations.

Shared taxonomy is the Google Product Taxonomy (free, has a Turkish file) plus Open Food Facts categories for grocery granularity. GS1 GPC rejected: full access requires paid membership.

### D10. Automation is a user-set dial, gated on measured reversion rate

Manual, semi-auto and full-auto. Manual is a permanent option, not an onboarding state: shipping auto-categorisation with no opt-out reliably triggers user revolt. Full-auto is gated on an observed correction rate, not a predicted confidence score, because confidence is not calibrated in a cold-start regime. Every full-auto action is undoable and appears in an activity feed.

### D11. Layered, legally defensible product data

Order: the tenant's own products, then an opt-in community catalog, then Open Food Facts in a separately-licensed isolated table, then a paid lookup on cache miss, then scraping as a last resort.

**GS1 Verified by GS1 is never cached.** Verified by reading the terms: clause 19.1 permits use "solely within your business... excluding any commercial use", defined as any use where the content is "made available as a whole or in part, on its own or as part of another product/service"; permanent copies are prohibited; and the Value-Added Product carve-out explicitly excludes replicating the content. Clause 8 makes the permission list closed: "If these Terms of Use do not specifically say that You can do something... then you cannot."

Scraping is retained as a fallback at Anılcan's explicit direction after the legal risk was raised. It is constrained: results never write to the shared community catalog, each source can be disabled independently, and the risk is recorded in `legal-and-privacy.md`.

### D12. Both interface modes ship, the user picks the front door

Assistant mode and inventory mode, switchable at any time. Neither is degraded.

Why: the 2025-2026 literature converges hard that chat is a strong capture surface and a weak system of record (no overview, no bulk edit, abandonment after two or three clarifying questions). Making it a preference resolves the tension as a product decision rather than a compromise.

### D13. Act first on parsed facts, ask later, never act on a guess

"1 adet süt aldım" writes the item, quantity and unit immediately, as a visibly incomplete row. Location, expiry and price are collected afterwards in one grouped card of tap-chips, never as sequential questions.

Guessed fields are never written silently under semi-auto. Every write is undoable and appears in the activity feed.

Why: intermediate confirmation beats confirm-at-end in controlled study, and asking on every turn trains users to ignore prompts. Every AI home-inventory product studied (Kept, Manifest, MovingBox, Bevel) populates an editable card and waits, none auto-commits.

### D14. Receipt ingestion is two features, not one with a fallback

Verified: for 2026 the Turkish invoice threshold is 12.000 TL VAT-inclusive (36.000 TL for jewellery), and document type is decided by buyer type. A business buyer receives an e-Fatura regardless of amount, so structured UBL-TR XML always exists. An individual under the threshold who did not request an invoice receives only a paper ÖKC fiş, so no XML exists anywhere.

Therefore: supplier purchases are parsed from structured XML at near-perfect accuracy, and market runs are parsed from a photo. Neither replaces the other. The threshold is inflation-indexed and moves annually, so it must not be hardcoded.

### D15. Email ingestion is forward-to-address in v1, OAuth in v2

A unique inbound address per tenant. Gmail's forwarding verification mail arrives at our own server, so it can be confirmed server-side and the user only adds the address and confirms once.

Google's requirement for `gmail.readonly` is verified from Google's own documentation: it is a Restricted scope requiring a third-party CASA security assessment renewed at least every 12 months. The assessment cost was reported as low hundreds to low thousands of USD per year, but **this figure is unverified**: the assessor's pricing page is JavaScript-rendered and returned no content. The decision does not rest on cost anyway; annual re-assessment, a review queue and disclosure requirements are unnecessary friction for v1.

App passwords with IMAP are not an option: Google removed basic-auth IMAP access.

### D16. MCP read-only in v1, write in v2

Streamable HTTP only. OAuth 2.1 resource-server behaviour with RFC 9728 metadata, delegating to Passport as the authorization server. Build against 2025-11-25 semantics, because `laravel/mcp` has no 2026-07-28 support yet (issue #277 open, zero comments as of 2026-07-30) and that revision removed the session model entirely.

`tenant_id` comes only from the verified token, never from a tool argument. The resource URI is tenant-scoped per RFC 8707. Tenant isolation tests are written before the MCP wiring.

Access is open on every plan with a plan-based **rate limit**, not a feature paywall. Of nine vendor MCP servers surveyed, only Notion hard-gates by plan; Atlassian scales rate limits; the other seven ship it free with the existing subscription.

Write tools in v2 use `preview=true` by default plus an idempotency key on apply, because the MCP spec has no confirmation primitive and no major client supports elicitation.

### D17. Three platforms, one Flutter app, mobile first

iOS, Android and web. No macOS, Windows or Linux. **One source, one feature set, one design on all three**: no platform-only screens, no feature hidden by platform, and layout that branches on width (`md:`, `lg:`) rather than on platform (`ios:`, `web:`). Design-concept driven on `magic` plus `wind`, with `DESIGN.md`, `design:sync` and a token allowlist, following the `uptizm` pattern.

Corrected 2026-08-06: an earlier version of this decision assigned roles per platform ("mobile captures, web reviews"). That was wrong and it was starting to leak into the code as a justification for layout choices. Where hardware differs the app uses what the platform offers (camera versus file picker) and the feature itself never moves.

None of the MVP's UI survives: it was landscape-locked with a fixed 320px sidebar, a desktop table abstraction and an eight-step modal wizard.

### D18. Label printing in v1 is A4 multi-label sheets, generated client-side

Dart `pdf` plus `barcode_widget`, laid out at exact millimetre dimensions. This removes the server Chrome and Browsershot dependency entirely, which was the MVP's most fragile operational component, and a label sheet is a deterministic grid with no JavaScript requirement.

Bluetooth thermal printers (Niimbot, TSPL) are a placeholder for later at Anılcan's direction. Two findings to carry into that decision: Niimbot firmware refuses non-genuine label rolls, verified from the maintainer of the leading reverse-engineered client ("Printer does not allow to print on non-rfid labels... This is firmware limitation"), and iOS cannot speak Bluetooth Classic SPP without MFi certification, which no Niimbot unit has. Protocol reference implementations exist under MIT (`niimblue`, `niimbluelib`, `AndBondStyle/niimprint`); `labbots/NiimPrintX` is GPL-3.0 and must not be copied into a proprietary codebase.

### D19. Filament stays, scoped to operations

Users, teams, subscriptions, basic statistics, inventory and location inspection, and log or audit tracking. Not the MVP's seven resources.

Reason it stays: we are selling AI credits and retention windows, so quota state, AI cost per tenant and manual subscription repair need a surface. Without one, the first billing problem is debugged in `tinker`.

### D20. Voice is push-to-talk in v1, hands-free in v2

Verified from the `speech_to_text` package's own documentation: it is "designed for short intermittent use... not continuous spoken conversion or always on listening", and iOS stops recognition tasks longer than about one minute. Android 17 additionally requires a foreground service with While-In-Use capability for background microphone access.

Published Turkish word error rates span roughly 3 to 18 percent depending on vendor, benchmark and domain, and vendor-published figures are the optimistic end. Do not quote a single number; measure with our own recordings in real cafe noise.

### D21. Identity costs zero code

`magic_starter` and `magic-starter-laravel` already ship login, registration, social login, password reset, 2FA with recovery codes, guest auth, phone OTP, device sessions, teams, invitations with token accept, member roles, profile, profile photos, notifications, email verification and timezones. Every hand-rolled equivalent in the MVP is discarded.

### D22. Saved filters are team-wide

`saved_filters(team_id, created_by)`. A cafe's "Yarın bitecekler" is useful to every shift, and the tenant boundary is already the team, so a per-user scope would mean each new employee starts from nothing and never sees the filter the owner built. Per-user privacy and a share toggle are what Linear and Jira need because their saved lists grow long enough to curate; a household or a small shop will have a handful.

Consequence: no "share" concept in the UI at all, which is the point. Revisit only if a tenant outgrows one scrollable chip row.

### D23. One column on every width, capped at `max-w-6xl`

No master-detail pane and no desktop table. Phone and desktop run the same widget tree, so there is one layout to maintain and one place a regression can hide. The cap earns its place on measurement rather than on a platform role: an uncapped product row across a full desktop window puts the quantity an eye-movement from the name.

Rejected: a two-column master-detail at `lg` (the Mail/Notes shape). It is the better desktop workflow for reviewing stock item by item, and the cost is that the detail screen stops being a page and becomes a pane, which changes routing while deep links still have to work, and every view then needs testing in two modes. Worth revisiting when the app has enough screens that the navigation cost is felt.

### D24. The expiry warning window is derived per product, not fixed

The window is the last fifth of the product's shelf life, floored at one day and capped at sixty. Milk (5 days) warns one day out; a tin (2 years) warns sixty days out. One global number cannot be right for both: seven days always warns about the carton and never warns about the tin.

The cap is load-bearing. A raw 20% of a two-year life is 146 days, which is noise rather than signal, and sixty days is where a tin becomes worth acting on.

Consequence: the filter carries no day count, because the window belongs to the product. "Yakında bitecek" is the chip label; "7 gün içinde" would be a promise the filter cannot keep. A product with an expiry date and no declared shelf life falls back to a 35-day life, giving the neutral 7-day window.

### D25. Two unit levels: a base unit plus one declared pack ratio

`products.base_unit` plus a content declaration (1 adet = 1000 ml; 1 paket = 3 adet). Stock is stored in ONE unit and converted on read or write, never as parallel per-unit columns.

Verified against every system that does this for a living: Odoo (one reference unit per category, `relative_factor` ratios, `_compute_quantity` converting at the boundary), SAP (everything converted to the base unit automatically, `MARM` per-material factors), NetSuite (one Base unit, with separate Stock/Purchase/**Consumption** units all converting to it), and xtraCHEF's Purchase Unit → Pack → Inventory Unit triple, which is the closest small-business precedent to "1 pack = 3 sachets" and is a single ratio rather than a tree.

**Two levels, not GS1's three or four.** GS1's each/inner-pack/case/pallet hierarchy is real and recursive, but it exists to give every physical repackaging boundary its own scannable, orderable identity across a distribution chain. That is an identification problem, not a quantity-conversion problem, and no general-purpose ERP copies it into its quantity model. Add a third level only if wholesale or multi-location ordering becomes real, and then as another flat named unit.

Turkish law already supplies the vocabulary for the pack case. Türk Gıda Kodeksi Etiketleme Yönetmeliği (RG 26.01.2017/29960 mükerrer), Ek-6: *"Bir hazır ambalaj birimi, aynı üründen aynı miktarda içeren iki veya daha fazla bağımsız hazır ambalaj biriminden oluşuyorsa, net miktar her bir ambalajın içerdiği net miktar ve ambalajların toplam sayısı verilerek belirtilir."* Per-pack net content plus total pack count is exactly the two fields this decision stores.

Two failure modes to avoid, both observed in the field: SAP's base unit cannot be changed once postings exist, and changing a conversion factor afterwards silently re-derives historical quantities with the new factor. So the base unit is immutable after the first movement, and a ratio change creates a new unit rather than editing the old one.

### D26. A partial quantity is shown as a count plus the open remainder, never as one decimal

"2 adet + 500 ml", not "2,5 adet". "2 poşet" with "(1 paket açık)", not "0,67 paket". The lot list gives the open item its own row with its own date.

Odoo's own answer is a per-unit Rounding Precision of 1.0 for anything that cannot be split, and its documented failure is that the precision setting is shared across all units, so users report seeing "2,345 chairs". Apicbase goes the other way and shows the fraction (2.5 packages of 500 g) because its package unit is mass-backed. This decision takes Apicbase's honesty about the remainder and drops the arithmetic nobody can picture: a number like "2,33 adet vanilya" corresponds to nothing a user can see in the cupboard.

### D27. "Opened" is a first-class lot state with its own expiry

`product_lots` gains `opened_at` and a shelf-life-after-opening in days; an opened lot carries its own derived date and reaches the attention list on that date rather than the printed one. Opening is recorded as a movement reason, so the ledger stays append-only and the derived balance stays correct.

An opened 1 L carton with 500 ml left is not half a litre of unopened milk: it spoils on a different schedule, and the product's whole waste-prevention claim breaks exactly there. Ten days on the printed date reads as "no problem" while the real limit is three.

This is a deliberate departure, not a copied pattern. Food safety already treats it as a distinct object: EFSA formally defines "secondary shelf-life" as the after-opening limit with its own decision tree, HACCP labelling practice requires the opening date on the label, and the Turkish labelling regulation requires an after-opening consumption limit to be declared where necessary. But no shipped inventory or ERP product models it: storq.io's lot statuses are Available/Quarantined/Expired/Consumed with no Opened, and Apicbase and WISK track partial containers as a fractional quantity on the same record with no shortened date. The concept appears in food-label printers and in patent literature, not in an inventory ledger. So there is nothing to copy and we are building it.

### D28. Lot tracking and serial tracking both ship in v1, chosen per product

A product declares whether its units are fungible (lot tracking: a batch with one expiry, quantities add up) or individually identified (serial tracking: one row per physical unit, its own serial or IMEI, its own warranty end date). Electronics, tools and appliances need the second and cannot be expressed by the first.

The cost was stated before the decision and accepted: the core model carries two shapes, so every screen, every filter and every movement record has to handle both, and v1 scope grows visibly. The alternative considered was warranty dates only, reusing the expiry machinery, with serials deferred to v2.

### D29. Never ask for unit, pack content or shelf life at capture time

Infer them: from the name ("1 lt", "3'lü"), from the barcode catalogue, from a category default. Ask later, and only where the answer changes what the app does. This is D13 applied to the unit model, and it is what protects the first success criterion (ten products into stock in under five minutes without reading anything).

Consequence: inferred values need a "not confirmed" mark, so a wrong guess is visible and correctable rather than silently load-bearing for a forecast.

## Open

### O1. Which payment provider for Turkey, and how it coexists with Stripe

Stripe is limited for Turkish legal entities. iyzico and PayTR are the candidates. App Store and Play Store in-app purchase is a third rail for mobile subscriptions and Apple's rules may force it.

Assumption until answered: iyzico for Turkish web checkout, Stripe for international web, and store IAP on mobile where the platform requires it. This means three payment paths and a `payments` table that already models provider per row.

### O2. Which vision model for receipt and product photos, and the credit price

Per-image cost spans an order of magnitude: Gemini Flash class around 0.003 to 0.004 USD per receipt, Claude Sonnet class around 0.015 to 0.025 USD, Claude Haiku in between. No vendor publishes Turkish receipt line-item accuracy, and no academic Turkish receipt OCR benchmark exists.

Assumption until answered: run a bake-off on 100 real Turkish receipts before choosing, price an AI credit at 0.05 to 0.10 USD per receipt to hold margin at the expensive end, and make the model a gateway configuration value so it can change without touching callers.

### O3. Whether KVKK cross-border transfer permits our LLM architecture as designed

Sending any personal data to a non-Turkish LLM is a cross-border transfer under KVKK Article 9 and needs a Kurul-approved standard contract or another lawful basis. The Kurul's decision 2026/347 of 2026-02-18 additionally requires the aydınlatma metni and the açık rıza metni to be separate documents; a single bundled acceptance checkbox is no longer valid.

This touches every AI feature, not only email: product photos, receipts, product names and assistant messages all cross the border.

Assumption until legal counsel answers: build the consent flow as two separate documents from the start, record consent per purpose with a timestamp and version, add a redaction step before any content reaches a model, and treat data residency as a real weight in provider selection rather than a tiebreaker. See `legal-and-privacy.md`.

### O4. Whether Turkish e-commerce senders emit machine-readable order data

Unverified in both directions: nobody confirmed whether Trendyol, Hepsiburada, Migros or Amazon TR include `schema.org/Order` JSON-LD in order confirmation emails. Also unverified: whether e-Arşiv PDFs reliably carry an embedded UBL-TR XML attachment in the ZUGFeRD style, which came from a single vendor page rather than GİB's own text.

Assumption until answered: design the email pipeline to parse JSON-LD when present and fall back to LLM extraction, and never assume an attachment exists. Verify by collecting real order emails from each sender.

### O5. How the community catalog earns contributions without becoming a liability

A tenant-contributed shared catalog is the moat, but it needs an opt-in, a moderation path, a takedown mechanism and a licence the contributor actually grants us.

Assumption until answered: contribution is opt-in per tenant and off by default, contributed rows carry `source = community` with the contributing team recorded privately, and the terms grant us a licence to redistribute the contributed fields but not the tenant's photos.

### O6. What the first paid tier actually costs in TRY

Turkish price sensitivity is the binding constraint on ARPU and we have no evidence about willingness to pay in this segment. Sortly's 24 USD entry is roughly 1.000 TRY, which is far too high for a Turkish small business.

Assumption until answered: model three price points and test them, and keep the MVP's mistake in mind, where Starter's TRY web price was entered as 9.99 against Plus at 399.99.

### O7. Whether the 2026-07-28 MCP revision migration lands in v1 or later

That revision removed the initialize handshake and the session model. `laravel/mcp` has no support and no stated plan.

Assumption until the ecosystem moves: build on 2025-11-25 semantics, keep the MCP layer thin enough that the transport can be replaced without touching the tools, and carry the migration as a known risk.
