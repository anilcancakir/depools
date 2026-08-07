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

### D30. The tracking mode is never asked at creation

Every product starts lot-tracked. "Seri numarası ekle" in the detail screen's overflow flips it to serial tracking the first time the user needs it, behind a confirmation that says it cannot be undone.

Nobody has a good plain-language version of this question. Odoo, Zoho, NetSuite, Katana and inFlow all ask it at creation in warehouse vocabulary (`By Lots` / `By Unique Serial Number`, `Batch Tracking` / `Serial Number Tracking`), and every one except Odoo locks it permanently once stock exists: Katana states outright that you "cannot switch from serial back to batch" and must create a new item, and inFlow calls the choice "permanent for each item upon saving for the first time". The one household-facing tool in that set, Sortly, has no lot or serial concept at all and tells users to hand-type a serial into a custom field.

So there is no wording to copy, and asking it would put a warehouse decision in front of a household user on their first ten products, against the five-minute criterion. Deferring is also the safe direction: lot to serial is the migration that works, and it is the one Odoo documents.

Cost, accepted: a shop selling electronics enters its first products in the wrong mode and converts them one at a time.

### D31. A draft field has three states and no confidence number

Every field on the draft card is loading, empty-because-the-model-was-unsure, or filled. The empty state says so and puts the cursor there; it is never left indistinguishable from an optional field the user chose to skip.

**No numeric confidence, anywhere.** No consumer product surveyed shows one, and the research is against it: well-calibrated confidence helps, miscalibrated confidence produces almost no gain while increasing both over-trust in wrong high-confidence answers and under-trust in correct low-confidence ones (AAAI 2026), and at least one controlled study found confidence categories shifted behaviour without improving accuracy at all. Calibration cannot be guaranteed in production, so the honest signal is a state, not a score.

Apple's own pattern is the same: Visual Look Up shows the affordance or it does not, with no in-between. Dext's "İncelenecek / Hazır" with a tooltip naming what is missing, and Expensify's field-specific failure message, are the precedent for wording the gave-up state.

### D32. A product saves with a name alone

`base_unit` is inferred: from the name ("1 lt" gives `adet` plus a 1000 ml content declaration, "5 kg" gives `kg`), from the category, and failing both it is `adet` and editable. This is D29 applied to the one field the schema will not accept as null.

Inferred values carry a "not confirmed" mark, because a wrongly inferred unit silently changes what every quantity in the ledger means.

Category is NOT required, even though it drives location suggestion through `location_category_affinity`. A mandatory taxonomy picker would be the slowest field on the form and users do not think in taxonomies; an uncategorised product simply gets no location suggestion until it has one.

### D33. Creation is the detail screen in draft state, not a second screen

The detail screen already owns the section structure, the identity card, the barcode list and the shared geometry, and it already has an empty variant. Creating a product lands on it with fields empty and editable; saving does not navigate anywhere, the same card carries on.

Rejected: a separate full page (two copies of the same section structure, and every later change made twice) and a full-height sheet (streaming fields, a photo, a barcode list and a tap-chip group do not fit one, and a phone keyboard halves the remaining height).

Cost: the detail screen carries a draft/saved mode on top of the two tracking modes it already carries. That is three combinations to keep exercised, and D28's record this session says each unexercised combination is where a defect hides.

### D34. The location tree gets its own screen, and the placement dial lives on it

Nothing in the app showed the hierarchy until now, even though every screen assumed it: the product detail lists stock per location, the filter offers locations as chips, the stock-in sheet suggests one. All of them presented a flat set of paths, so the structure the schema maintains (`parent_location_id`, a materialised `path`, depth capped at 6) existed nowhere a user could see or edit.

`location-assignment.md`'s automation dial belongs on that screen rather than in settings. What it automates is exactly what the screen is about, and the dial is meaningless before the user has a tree for it to choose from.

**The dial states what each position does, not just its name.** "Otomatik" alone does not tell a user that a placement will happen without being asked, which is the part they would want before choosing it. And because full-auto is gated on a measured reversion rate rather than a predicted confidence, the screen says the setting can drop back on its own: the dial is a request, not a guarantee.

The empty state is a **blocker, not decoration**. A tenant with no locations cannot receive stock anywhere, so it is the first screen of every account and it offers two ways out: add one, or start from a template.

### D35. A location row shows its own name; the count includes descendants

In the tree, a row shows only its own name, because the ancestors are literally on screen above it. Repeating "Mutfak › Buzdolabı" inside a hierarchy is the redundancy that makes a hierarchy unreadable. `LocationStockRow` on the product screen does the opposite for the opposite reason: there the tree is absent, so the path is the only context.

The count is the subtree's, not the node's own. "Mutfak, 5 ürün" means everything in the kitchen, which is what a user reading it means; a parent showing only what sits loose in the room would report 0 for a kitchen full of food.

**Depth is expressed by indent, and the gutter is reserved on every row.** Rendering the icon conditionally inverted the tree: a root with an icon had its name pushed 32px right by the glyph and gap while its child got 12px of indent, so children appeared to the LEFT of their parents. Indent is `pl-3` per level, which keeps the schema's deepest row inside 60px on a phone.

### D36. Lists are cursor-paginated with infinite scroll; the URL carries the query, not the cursor

Both list screens rendered every row with no paging at all, which works on a fixture set and not on a tenant with a thousand SKUs.

**Cursor, not offset.** In an inventory app stock changes while the user scrolls, so an offset page skips or repeats rows the moment anything above the window moves. A cursor on the sort key is stable under insertion, which is the property that matters here more than the readability of `?page=3`.

**The URL carries the search and the filters; it does not carry the cursor.** A filtered list is worth addressing and sharing, a scroll position is not, so a reload lands at the top of the same filtered list. That is also what a user expects from a link someone sent them.

**The footer has three states and they must not look alike**: a page in flight, the end of the list, and a failed page. A list that silently stops paying out is indistinguishable from one that finished, and a failed page showing nothing looks like the end of the data. Same class of failure as an invisible active filter: the screen is short and does not say why.

Two details worth keeping:

- **Skeleton rows, not a spinner**, and as many as the page size. The rows are the shape of what is coming, so the space is reserved and the list does not jump when the page lands.
- **The end state states the total.** It is the one number worth having at the bottom of a stock list, because it is also the unique-SKU count the plan meters on (D4), so a user glancing at it learns something they would otherwise go hunting for.

### D37. The location tree gets search and a three-way scope, and a filtered tree shows paths

Search plus `Tümü / Stok var / Boş`, in the same layout the stock list already uses. Two list screens that search differently is a cost paid on every visit, and a tree does not need a different affordance to be searched.

Three positions rather than a filter sheet, because a location tree has one axis worth filtering: whether a place currently holds anything. A tenant hunting an empty shelf to put something on, and one auditing what is where, are the two real cases.

**A filtered tree loses its ancestors, so indent stops meaning anything and each match falls back to its full path.** A row inset two levels under nothing reads as broken. This is the one place D35's own-name rule gives way, and it gives way for D35's own reason: the path appears exactly when the tree is not on screen to supply it.

**Every node carries an icon, children included.** A tree where only roots have a glyph makes children read as text under a heading rather than as places, and `locations.icon_id` exists on every row. Making the icon required rather than optional also removed the conditional-glyph bug that had inverted the indent, which is the stronger fix: delete the state instead of padding around it.

### D38. A move is one draft, and both of its endpoints are constrained at the tap

The transfer sheet commits a single `StockMoveDraft` that becomes the movement pair, rather than two independent entries. Invariant 5 requires equal and opposite deltas with a shared reference, and the surest way to keep them equal is to never let a caller author them separately.

**The source list holds only locations with stock; the destination list excludes the source.** A picker offering everything on both sides lets a user build a move of nothing from nowhere, and the error then arrives at commit instead of at the tap. The destination list derives from the chosen source and re-derives when it changes, which also clears the amount, because the amounts a source can offer depend on what it holds.

**The destination suggestion falls through affinity by design.** Category affinity usually names where the stock already sits, which is the one invalid destination, so skipping to the next option is the normal path rather than an edge case. This is the first place the affinity model's best answer is routinely wrong for structural reasons, and it is worth remembering when the real model replaces the fixture.

### D39. Provenance is printed only when the answer is not the tenant's own inventory

`barcode-and-catalog.md` asked how to show provenance "without cluttering the UI ... should
not have to read a source label on every row", and the answer is that silence means
authoritative. A hit in the tenant's own products carries no source label; a catalog hit,
an unverified hit and the user's own replayed manual entry each carry one word.

Same logic as `DraftField`'s unconfirmed mark: the annotation belongs where trust is lower,
not everywhere. A label on every row costs a reading pass per row and communicates nothing
on the rows that need it least, which is the definition of clutter.

Five named sources rather than a confidence percentage, for the reason D31 already settled:
a number invites arithmetic the user cannot act on, while a named source says exactly how
far to trust the row. Criterion 7 (a scraped row is presented as unverified) is satisfied by
the `unverified` source carrying `Doğrulanmadı`.

### D40. A repeat scan increments its row, and the queue is ordered by last scan

Six identical yoghurts are one row reading six, not six rows. The consequence is not
optional and is the actual decision here: the queue must be ordered by LAST SCAN rather
than by first-seen, because otherwise the sixth scan increments a row that has already
scrolled off and a scan that worked produces no visible feedback.

This is deliberately the opposite of the receipt review screen, which groups unresolved
lines first. The paper is static there and triage is the task; here the camera is live and
feedback beats triage. Unmatched rows stay in place and a count above the commit button
carries them instead.

### D41. The scan batch has one destination, and it is the last receiving location

Receiving and putting away are two events. Everything in a batch lands where it was
received, and splitting it across shelves is the transfer flow (D38), not a per-row picker
at the bench. Asking for a destination per row would ask the user to decide, with a box in
their hands, something they only know once standing at the shelf.

The default is the last location used for receiving, **not category affinity**, which is a
deliberate departure from every other location suggestion in the app. Affinity answers
"where does this CATEGORY go", and a batch of milk and screwdrivers cannot ask that
question; picking one row's winner for the whole batch would be arbitrary dressed as
intelligence. Receiving location is a habit rather than a per-product fact.

### D42. The label flow is one screen with three sections, not a three-step wizard

`labeling-and-printing.md` describes three steps and names what it is reacting to: "the
MVP's eight-state modal machine with no back button". Criterion 4 then asked for three steps
where every step has a back path.

One screen satisfies that in its strongest form rather than its literal one. There is no
sequential gate, so every decision is reachable at every moment and a back path is not
something to implement and get wrong. It also puts the sheet preview beside the template
list, so switching templates shows its effect immediately, which is the comparison the
screen exists for. Criterion 4 has been reworded to match; the literal three-step count was
a proxy for "not eight", and the proxy is weaker than the thing it stood for.

Every other capture surface in this app is already shaped this way (draft form, receipt
review, scan queue), so the wizard would also have been the only one.

### D43. Two previews: one dimensional, one legible, and the empty cells are drawn

The sheet renders at true A4 proportions and one label renders separately at a readable
size. A single zoomable view has to choose, and at sheet scale 9pt type is about six pixels:
rendering it is noise, and rendering it larger would let a user approve a name that does not
actually fit, which is criterion 7 failing in the direction that costs a sheet of labels.

**Empty cells are drawn rather than left blank**, because paper is the consumable and
picking a template is picking how much to waste. The template list carries pages AND blank
cells for the same reason: on a 21-label batch, 24-up and 65-up are both "1 sayfa" and one
of them prints 44 blanks.

Consequence for the implementation: the geometry is Flutter (`AspectRatio` plus `Expanded`
flexes that are the millimetre figures times ten) and only the paint is Wind, because Core
Law 3 forbids interpolating a computed value into a className. The preview is exact by
construction rather than by a scale factor somebody has to keep right.

### D44. Paper and ink are fixed token pairs, identical in both appearances

Every other colour in the app flips with the appearance because every other surface is read
on a screen. A label preview is a picture of paper, and paper is white at two in the
morning. So `bg-paper`, `text-ink`, `text-ink-muted`, `bg-ink` and `border-color-ink-subtle`
hold the same hex on both sides of their `dark:` pair.

They live in `lib/config/depools_paper_tokens.dart`, deliberately NOT in the status
supplement: `bin/verify-design-contrast.py` parses that file as a status vocabulary and
checks every solid against `surface-container`. White paper against a light app surface is
about 1.05:1 and would fail that check for the right reason applied to the wrong question.
The verifier gained a PAPER section that checks ink against paper instead, and asserts that
both halves of each pair are identical so the fixed-ness cannot drift unnoticed.

`ink` is true black rather than DESIGN.md's near-black, because that rule exists to stop
pure black reading as a hole punched in a screen surface, and toner on paper is simply
black.

### D45. A label count means two different things, and the row says which

A lot-tracked product's label identifies the PRODUCT, so twelve stickers are twelve copies
of one design and the count is free. A serial-tracked product's labels are all different,
one per unit, so its count is the number of selected serials; a stepper there would be
offering to edit how many units exist. A printed line loses its stepper for the same kind of
reason: its labels are on a sheet already, so changing the count would describe a past
event.

In both cases the control is ABSENT rather than disabled. That is the same call the stock
sheets make, and for the same measured reason: a disabled `MSButton` in the primary intent
looks identical to a live one, so a disabled control invites a fight the user cannot win and
gives no feedback when they try.

### D46. The precision of the sentence is the uncertainty display

`forecasting.md` left this open, noting that no good precedent was found for showing a
probabilistic inventory forecast to a non-technical user. The answer is to let the LANGUAGE
degrade with the data rather than invent a visual vocabulary for doubt. A line makes only
the claim its tier supports:

| History | What the line says | Shape |
|---|---|---|
| 10+ movements | `2 günlük kaldı` | a number |
| 2 to 9 | `Yaklaşık bir hafta · geçmiş az` | a bucket, never a number |
| 0 to 1 | `Hedefin altında · 0 / 2 adet` | a ratio, no time claim at all |

Nothing new has to be learned, a bucket cannot be misread as a measurement, and it fails in
the safe direction. It is what weather forecasts do for the same reason: "rain this
afternoon" when the model cannot say three o'clock.

Rejected: a confidence percentage (D31 already settled that a number invites arithmetic
nobody can act on), and error bars (they read as noise to someone who does not read charts).

Corollary that cost a fix here: zero on hand says `Stok bitti`, not a days-of-cover figure.
An earlier fixture said "1 günlük kaldı" for a product whose own amount was 0, because the
quantity was derived from the product and the sentence beside it was hand-written. Derive
both or neither.

### D47. Ticking a shopping line is not a stock movement

A tick means the item is in the trolley. Stock arrives when the receipt is scanned or a
stock-in is recorded, and nowhere else.

The alternative gives every user phantom inventory for everything they picked up and put
back, and double-counts as soon as the receipt lands. It also breaks the ledger's own
story: a movement's `source` records the surface that created it, and "the user ticked a box
in a shop" is not evidence that anything arrived.

Design consequences: ticked lines sink into their own group rather than vanishing, so the
remaining list shortens while a mis-tick stays findable; the group keeps each line's reason
rather than replacing it with "in the trolley", because the reason is what the user checks
the quantity against while holding the thing; and the receipt action appears only once
something is ticked, since that is when it means anything.

### D48. The lead time we need is the user's restock rhythm, and it is never asked

`forecasting.md` left this open with three options: ask per product, infer it, or use a
global default. Asking is disqualified on its face. "What is the supplier lead time for
milk?" is the kind of question that ends a household user's relationship with a product, and
`product.md` is explicit that our user does not understand reorder points and should not
have to.

Infer it, and infer the right thing: for a household or a cafe the delay that matters is not
a supplier's, it is **how often this tenant restocks**, which is directly observable as the
interval between purchase movements. A global default covers a tenant with no purchase
history yet, and the inferred value replaces it as soon as there is one.

The phrase "lead time" never reaches the interface. What the user sees is its consequence,
in the reason line: an item appears on the list early enough that their normal shopping
rhythm covers it.

### D49. The assistant answers with components, never with prose about state

`ai-assistant.md` calls this the hardest design problem in the product: how assistant mode
presents the stock overview a transcript cannot give, and getting it wrong is what makes
chat-first apps fail. Its own diagnosis names two failures, so there are two answers. This
is the first.

A question about shortages returns the same `ShoppingRow`s the shopping list renders. A
write returns the same `MovementRow` the product's history will show. An approval renders
the movement pair it will write. The assistant's sentence is a caption over the component,
not a description of it, which is also why it gets no chat bubble: two facing bubble columns
make a work surface read like an instant messenger.

Four things follow, and the last one is why this is worth a decision rather than a style
note:

- Scrolling back shows state changes, not sentences about them, so there is nothing to
  reconstruct.
- Every answer is tappable through to the real screen, which turns criterion 7 from a
  promise into a link.
- Prose about numbers is exactly where a model would be doing arithmetic, which D7 forbids.
- **The assistant cannot disagree with the app it sits in**, because it is rendering the
  same component from the same source. This codebase has already shipped a list and a
  detail page contradicting each other about one product; an assistant is the surface where
  that failure would be most expensive.

### D50. The overview is chrome, and the activity feed is a panel over both shells

The second half of the same problem, plus the open question next to it.

**The overview never enters the transcript.** Three derived figures sit above it: what is
close to its date, what is running low, what has no target level. Anything inside a
transcript scrolls away, and a summary that scrolls away is not a summary. The figures are
counted from the same fixtures every other screen counts, for the reason in D49.

The third figure is the app's own silence made visible: a product with no target level can
never reach the shopping list however low it gets, so "3 ürün hedefi yok" tells the user why
they are not being warned. A first pass counted products with no CATEGORY and rendered "0
ürün", which was true and useless.

**The activity feed is a panel, not a screen and not a sidebar.** It opens from the header
in both shells. In assistant mode the writes are already in the transcript with undo; in
inventory mode they are on each product's movement list. The panel is the cross-cutting
"what happened while I was not looking" view, which full-auto makes necessary. A dedicated
screen would be a third place the same rows live, and a permanent sidebar would give
occasional review permanent real estate.

### D51. Undo appends a compensating movement, and both rows stay visible

The ledger is append-only, so there is no version of undo that removes anything. Reversing a
write appends a `correction` referencing the original, and the feed shows the pair: the
correction on top, the original faded beneath it.

Collapsing the pair into one row was the tempting alternative and it is wrong twice over.
The balance is the sum of the deltas, so a history that hid one of them would not reconcile
by hand, which is exactly what `forecasting.md`'s second criterion asks a person to do. And
an audit trail whose visible row count differs from the ledger's is one nobody can trust at
the moment they most need to.

The cost is real and accepted: a mis-tap followed by an immediate undo leaves two rows
forever. That is what an append-only ledger means, and the alternative trades a permanent
correctness property for a temporary tidiness one.

Presentation detail that came out of the screenshot: the faded row keeps its NOTE at full
foreground weight. `text-fg-disabled` under a 50% fade is unreadable, and "Geri alındı" is
the one thing the row still has to say.

### D52. Undo is offered exactly when it would work, and otherwise the row says why

Validity is a question about ledger state, not about a clock, so there is **no time window**.
An undo a month old is fine if the compensating movement would still keep the invariants; an
undo from a minute ago is impossible if a later movement already consumed the lot.

When it would not work, the row carries the blocking fact where the button would have been:
`Geri alınamaz · bu partiden 0,8 kg kaldı`. Not a greyed button, for the reason established
across this whole design: a disabled `MSButton` in this theme is visually indistinguishable
from a live one, and even a visibly disabled control with no reason is a dead end.

A correction is not itself undoable. Undoing an undo is a third movement nobody asked for.

### D53. Saving a field clears its `otomatik` mark, and so does confirming it unchanged

An inferred value carries a mark. Both ways out of that mark are one tap: change it, or open
it and save it as it stands. Dismissing without saving leaves the mark, because looking is
not confirming.

The point is that the marks DECAY as the draft is reviewed. The alternative, where only an
edit clears the mark, leaves a permanent field of `otomatik` labels on every value the model
got right, which is most of them: the annotation would end up marking "the app filled this
in correctly" forever, and a mark that never goes away stops being read.

It also gives the screen a finish line without adding a completion bar: a draft with no
marks left is one the user has been through.

The sheet says this above its save button. A mark disappearing after the user changed
nothing is otherwise a small surprise, and small surprises in a form are what make people
stop trusting it.

### D54. The unit is freely editable in a draft, and nowhere else

Changing `adet` to `kg` reinterprets every quantity in the ledger. In a draft there is no
ledger, so the edit is free and the field editor offers the full list.

Once a movement exists it stops being a field edit. Recording this because the same editor
is one wire away from the saved product screen, and the failure would be silent: a product
whose history says 12 with no indication that six of them were counted before the unit
changed.

The editor's number mode already keeps the two apart visually: the unit sits BESIDE the
input rather than inside it, because changing what a number means is a different decision
from changing the number.

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
