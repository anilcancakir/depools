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

> **Superseded by D66.** There is one home, the overview. The preference survives in a smaller form:
> it picks which capture verb is pinned at the TOP of that home, not which front door opens. The
> reasoning below about chat being a weak system of record is what D66 kept; the conclusion that it
> justifies two shells is what D66 rejected, because the 2026 literature is united against hybrid
> front doors and two shells double the surface to maintain. Kept in place rather than deleted, so
> the argument that produced it stays readable.

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

### D18. Label printing in v1 is A4 multi-label sheets, rendered on the backend

> **Reversed 2026-08-10 at Anılcan's direction.** The paragraph below argued for generating the
> sheet client-side in Dart, and the argument was sound about the RISK it named: server Chrome was
> the MVP's most fragile operational component. It was wrong about the alternative being free.
> Rendering the same sheet twice, once in Dart for the preview and once for the file, means two
> layouts that drift; the printable artefact is a PDF whatever produces it; and a Dart-drawn grid
> has to re-implement text fitting, barcode symbology and page geometry that an HTML renderer
> already does. So the MVP's shape returns deliberately: an HTML template rendered to PDF on the
> backend.
>
> What that costs is recorded in `features/labeling-and-printing.md` rather than waved away, because
> the fragility D18 originally fled is real and four specific parts of it are now named with their
> mitigations: exact millimetres need `preferCssPageSize`, Turkish glyphs need the fonts installed
> in the render image, assets must be inlined, and Chromium's print media strips backgrounds unless
> told otherwise.

The original reasoning, kept because the risk it names has not gone away: Dart `pdf` plus `barcode_widget`, laid out at exact millimetre dimensions. This removes the server Chrome and Browsershot dependency entirely, which was the MVP's most fragile operational component, and a label sheet is a deterministic grid with no JavaScript requirement.

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

> **Half of this was corrected by D70.** The dial rendered UNDER the tree, which scrolls without bound, so it was unreachable for exactly the tenant with enough locations to care. And a preference living on one screen only is a preference nobody finds. The value now lives in `AppPreferences`, Ayarlar holds the canonical copy, and this screen keeps a folded shortcut ABOVE the tree with the current position in its header. The argument for the shortcut being here still stands; the argument for it being ONLY here does not.

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

### D55. The dates screen gets an absolute horizon; D24's window keeps its own job

The first version of this screen filtered each row on its product's own D24 window (the last
fifth of shelf life, floored at one day). It produced **zero rows**, and the reason is worth
keeping: for a five-day milk that window is one day, so a carton with two days left was
excluded from the one screen built to find exactly that carton.

The two thresholds are not competing definitions of "soon". D24 decides what earns a badge
UNPROMPTED, on a screen the user did not open to ask about dates, and it has to be
conservative or every product shouts. This screen IS the question "what is coming up", so its
scope is a time horizon the user controls (3 / 7 / 30 days, default 7), and urgency inside it
is carried by `ExpiryBadge`, which has a threshold tuned for exactly that.

This also un-contradicts the feature doc, which said "what expires in the next N days" all
along. The earlier draft treated that phrasing as a mistake to correct; it was right.

The general lesson, and the reason this is recorded rather than quietly fixed: **a derived
threshold that is correct for an alert is not automatically correct as a filter.** Measure a
fixture before designing against it. One probe caught this; a screenshot would have shown an
empty state and I would have shipped it as the populated one.

### D56. Every row on the dates screen is a lot, including the products that have none

A product with a lot breakdown contributes one row per lot. A carton expiring Tuesday and one
expiring next month are two different decisions, and showing the product would tell a user
that something needs using without telling them which one to reach for. The fixture proves
the case: the same milk appears twice, at two dates, in two locations.

A product carrying a single date contributes one row too: its implicit lot. So there is one
row type with no exceptions, `forecasting.md`'s "a date comparison over lots" holds literally,
and the rule states cleanly as **the row is the finest-grained thing that has a date**.

Grouping is by location because the doc asks for it and the use case is why: a cafe's morning
check is a walk to the fridge, then the freezer, then the dry store. That is the opposite call
from the shopping list, where urgency ordering beat aisle order, and the difference is that
there the reason column carried the trust and here the walk carries the task.

### D57. Running low is the diagnosis, the shopping list is the action

The two surfaces show nearly the same rows, which made it worth asking whether the second
one earns a screen at all. It does, and the split is what each is for.

Running low answers **what is short and how sure are we**: the target, the days of cover
where a cover figure exists, and which certainty tier the product is in. Its rows are not
tickable, dismissable or reorderable, because a diagnosis is not a document the user edits.
The shopping list answers **what do I buy**: one line per thing, a reason phrase instead of
figures, tick-off state, and a receipt at the end of it.

So the tier shows up twice in two forms, and both read it from the product rather than
deciding it locally: the shopping list turns it into the SHAPE of a sentence (D46), and this
screen turns it into a group heading with a line saying what that group may claim. A user
who wants to know why the app is confident about the bulgur and vague about the milk can
read it off the screen instead of trusting the ranking.

**Containment runs one way, and a test says so.** Every product here is on the shopping
list; the list is a strict superset because it also carries expiring rows (an opened yoghurt
is running out of days, not of quantity) and manual ones. Asserting equality would assert
something false. The test exists rather than a comment because this app has already shipped
a list and a detail page disagreeing about one product.

**Out of stock is its own group.** Zero is not a degree of short. It leads, it does not fold,
and it sits above the tiers so a well-forecast product with four days of cover never outranks
something already gone. Its rows also drop the cover figure: "0 günlük kaldı" under a heading
reading "Stok bitti" is a true statement adding nothing.

### D58. A count is blind until a number is entered, then immediately informed

No expected figure appears next to an uncounted row on the stock-take screen. Warehouse
practice calls this a blind count and the reason is anchoring: a counter shown "5" will look at
a shelf and see five, which turns a count into a confirmation and makes it worthless as a check
on the ledger.

The moment a number is entered, the system figure and the difference appear. So the anchoring
is avoided while it matters and the feedback arrives while the user is still standing in front
of the shelf, which is the only moment a discrepancy is cheap to investigate.

Rejected: a fully blind count with the variance shown only at the end. It is what enterprise
systems do, and it is wrong here because our user is often the same person who put the stock
there; making them walk back to the fridge to resolve a variance they could have seen
immediately is friction that ends with counts not being done.

**An empty field means NOT COUNTED, never zero**, and the placeholder is a dash to say so. An
uncounted row is left completely alone at commit; a zero writes the whole balance off. A sheet
whose empty field meant zero would zero out every product the user did not reach, which is the
worst failure this screen could have.

### D59. A count writes `stock_take`, and a match writes nothing at all

`data-model.md` separates `stock_take` ("a counted correction after a physical count") from
`correction` ("fixing a data-entry error"), and a count uses the former. The two exist
separately for the same reason `waste` is not folded into `consumption`: without the split you
cannot tell stock that walked out of the building from a number somebody mistyped, and
shrinkage is a figure a business pays for.

**A count that agrees writes no movement.** Nothing changed, so there is nothing to append, and
a zero-delta row would not be harmless bookkeeping: `movementCount` is what decides whether a
product has enough history to be forecast, so counts would promote products into the forecast
tier on the strength of having been looked at. The commit line says so outright
(`eşleşen sayımlar hareket üretmez`), because "I counted 12 things and it saved 1" needs
explaining before it looks like a bug.

### D60. The shelf photograph stays on screen with numbered boxes, and the rows carry the numbers

`ai-enrichment.md` sketched a film strip of candidate crops. The photograph IS the strip, so the
boxes are drawn on it and the rows are numbered to match, which gives the same spatial link
without generating a second set of images.

The number is doing real work and it is why this is a decision rather than a rendering detail.
It is the ONLY thing tying a row to a region: order cannot do it, because rows get filtered and
reordered while boxes stay where the shelf put them. So the number renders on every row at a
fixed width, in mono, and `test/shelf_photo_test.dart` asserts the numbers are unique and
contiguous from one, because a gap would point a row at nothing and a duplicate would point two
rows at the same box.

It also works with no hover and no tap state, which matters twice: a static design review has no
pointer, and a screen reader has no way to perceive a highlight.

**The accept count is the settled count, never the region count.** Six regions yielded four
products in the fixture; a button labelled six would promise to write an unnamed bottle and a
price label the recogniser mistook for stock. A test locks that too.

Rejected candidates fade and stay rather than disappearing, for the same reason a reversed
movement does (D51): a row that vanished on rejection is one the user cannot un-reject.

## Open

> **The file is append-only, so this heading is not a clean boundary.** Decisions taken after O1 to O5
> were appended below them rather than moved up, which means **D61 through D92 are TAKEN decisions
> sitting under this heading**. Do not read a `D` number here as an open question.
>
> What is genuinely open, in full: **O1** payment provider for Turkey, **O2** vision model and credit
> price, **O3** whether KVKK cross-border transfer permits the LLM architecture, **O4** whether Turkish
> senders emit machine-readable order data, **O5** how the community catalog earns contributions,
> **O6** what the first paid tier costs in TRY, **O7** whether the 2026-07-28 MCP revision lands in v1.
> Seven, and each carries the assumption we proceed on until it is answered.

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

### D61. Every built screen is routed, and the dashboard is the app's own

For months this app registered exactly ONE route, `/` to the dashboard, while twelve designed and
verified screens existed only as entries in the `/preview` catalog. The sidebar offered Dashboard
and Settings. A screen nobody can navigate to is not shipped however green its preview is, and the
gap was invisible because every review happened inside the catalog, which reaches a screen by class
rather than by URL.

`lib/routes/app.dart` now registers ten routes under the authenticated shell, with Turkish plural
paths (`/tarihler`, `/azalanlar`, `/urunler`) because a URL is user-facing on web and `/products`
reads as a scaffold's while `/urunler` reads as this product's. The sidebar carries nine entries and
the bottom bar five.

The views still render fixtures rather than controller state, and routing them BEFORE wiring
controllers is deliberate: it puts every screen inside the shell it will actually live in, which is
where header offsets, bottom-nav overlap and scroll ownership surface. None of those are visible in
a preview pane. It found two on the first run.

### D62. A dashboard card shows three rows and says how many it hid

Each card caps at three rows and then renders a `ListFooter` naming the true total
(`5 parti içinden ilk 3 gösteriliyor`). A dashboard that renders a whole list is the list screen
with extra steps; one that truncates silently teaches the user that the counters above it are
decoration.

Three rather than five because the four cards have to coexist above the fold on a laptop: measured
at 1400x1000, three rows each puts the last card's header just inside the viewport.

The shopping card is the exception and shows a sentence instead of rows. The other three are FACTS,
which a partial view of is still useful. The shopping list is a DOCUMENT the user works through with
a phone in one hand, and a partial copy of it invites ticking items off in the wrong place.

### D63. Every figure on the dashboard is derived from the destination screen's own source

Not one number on the dashboard is typed. Each counter is the length of the collection the card it
sits above renders, and each of those is the same fixture the linked screen reads, so the summary
cannot disagree with the page it links to. `test/dashboard_test.dart` asserts the RELATIONSHIPS
rather than literals: a test reading `expect(expiredRows().length, 1)` would pass while the
dashboard displayed something else, and would fail on any honest fixture edit.

The load-bearing one: the dates card sums `expiredRows()` with the flattened
`approachingByLocation()`, and that grouping walks `locationOptions`, so a lot in a location the
option list does not name would vanish from the group map while still counting on the dates screen.
The test asserts the two halves add up to `datedLots()`.

The counters are a `grid grid-cols-2 md:grid-cols-4 items-stretch`, not a row. The assistant learned
this in the other direction: three stat cards in a plain row came out three different heights,
because their labels wrapped unevenly at phone width. On a grid, `items-stretch` makes a row's cells
match its tallest, so four values share one baseline at every width with nothing measured in Dart.

### D64. "Caught up" and "not started" are two different empty screens

Both produce four zeroes on the dashboard, and the first version of that screen showed the same
calm `Bekleyen iş yok` for both. To someone who signed up ten seconds ago that reads as the app
claiming their work is done, at the only moment they are deciding whether the setup is worth their
afternoon.

A tenant with no stock gets a DIFFERENT screen rather than a thinner one. The counters, the four
cards and the movement history all describe stock, so every one of them would render as a zero or
an empty state: six ways of saying the same nothing.

The checklist is three steps in the order the data depends on itself. Locations first, because a
product with nowhere to be cannot be counted and cannot appear on a per-location dates walk.
Products second. Targets third, and a step rather than a detail because a product with no target
can never appear in `Azalanlar` however low it gets, so the screen would stay empty and look
broken. The running-low empty state already says this; the checklist says it before it can bite.

Each step carries what it BUYS rather than only what it is, because a first-run user has no model
of the product yet and will not infer why locations matter.

**No capture card on this screen, and dropping it fixed two things.** The first draft reused the
populated dashboard's `Ekle` row, which offered `Sayım yap` to a tenant with zero products: an
action that cannot succeed, landing on an empty count and teaching the user that the buttons are
decorative. It also put a second `bg-primary` on the page beside step 1's marker, which DESIGN.md
allows exactly one of. The steps already carry the actions in the right order.

`SetupStep`'s marker gutter is a fixed `size-8` box whose CONTENTS change between a number and a
tick. `.claude/rules/design.md` forbids a conditionally-rendered leading glyph because it shifts
the text beside it; a fixed box is what makes the change safe, and the titles share one x across
all three states.

### D65. An overlay border is a PAIR of strokes, and that is arithmetic rather than taste

Two surfaces draw UI over an uncontrolled background: the barcode viewfinder's framing rectangle
and the shelf photo's numbered region boxes. Both used `border-color-border`, a `#D1D1D6` hairline
that vanishes over a white shelf label or a bright camera frame, and neither could borrow
`bg-primary` because `border-bg-primary` drops silently (the alias expander matches a WHOLE token
against a key, finds nothing, and the border parser then sees an unknown colour).

DESIGN.md deferred the token, and the reason was correct for what it was considering: picking one
hex against a placeholder rather than a real photograph is guessing at the thing that matters,
because the right value depends on the image.

**A single stroke cannot escape that dependency. A pair can.** For a background of relative
luminance L, contrast to a light stroke is `1.05 / (L + 0.05)` and to a dark stroke is
`(L + 0.05) / 0.05`. They move in opposite directions, so the better of the two is worst exactly
where the curves cross and nowhere else. Ideal black and white cross at 4.58:1; the chosen values
cross at **3.91:1**, above the 3:1 WCAG 1.4.11 asks of a UI-component boundary. That figure is a
floor over every background that can ever exist behind them, so there is nothing left to guess and
the deferral no longer applies.

`border-color-overlay-ink` (`#1C1C1E`) outside, `border-color-overlay-paper` (`#F2F2F7`) inside,
drawn as two concentric strokes. Both pinned identically on each side of `dark:`, like the paper
tokens, because an overlay's background is a photograph rather than a surface the app controls.

Not pure black and white: that buys 0.67 of a contrast point and reads as a rendering artefact
rather than as interface, the same objection DESIGN.md raises to pure black text on a saturated
fill. The two strokes are 15.25:1 against each other, so the boundary between them is never the
weak link.

`bin/verify-design-contrast.py` sweeps the whole luminance range and fails the build below 3:1,
rather than trusting the arithmetic in the docs.

### D66. One home screen, and the mode preference becomes the pinned capture verb

`product.md` used to offer two front doors chosen by the user: an assistant mode where chat is the
home, and an inventory mode where the stock list is. The 2026 literature on conversational
interfaces is unusually united against that shape. Design Key (2026-05): "they pick one pattern and
commit, no hybrids", and it names forcing a conversation for a transactional question as always
worse than a screen. Adaline (2026-06): the products winning now put the AI behind a verb, a canvas
or a delegation rather than behind a prompt, with the diagnostic "could a new user finish a real job
in under ninety seconds without typing a sentence". The Conversation Trap (2026-03): conversation is
for meaning-making, direct manipulation is for doing, and there is a hidden literacy tax on prompt
writing that fluent communicators still pay.

Two front doors is the hybrid all three warn about. It doubles the surface to maintain and makes a
blank text box the first thing a whole class of users sees, which collides with this product's own
first success criterion: ten items into stock in under five minutes without reading anything.

So there is one home, the overview, and the preference decides which capture surface is PINNED at
the top of it: the assistant composer, or search plus the stock list. The choice stays the user's,
the pattern stays single, and the assistant is behind a verb rather than being the whole door.

The overview itself was not in any document before it was built, which is the other half of this
decision: it is now the named home rather than an unrecorded third thing.

### D67. The assistant is persistent on every screen, and can be turned off

D66 puts the AI behind a verb. This decides how big that verb is, and the answer is bigger than the
research alone would suggest, for a product reason the research does not know about: **every
capability in Depools is reachable through the assistant.** Stock movements, adding a product,
scanning a barcode, setting a par level. The assistant is not a feature sitting on the product, it
is the layer the product is meant to be operated through, and an affordance that only exists on one
route contradicts that.

So it is persistent, on every screen, rather than a route with a button pointing at it.

The concession that keeps this honest is the settings toggle. The literature's objection to
chat-everywhere is that it taxes users who would rather click, and a persistent affordance they
cannot dismiss is exactly that tax made permanent. A user who wants the conventional path turns it
off and never sees it again. That is what earns the persistence: always within reach, never in the
way.

Two constraints this puts on the design, both from `DESIGN.md`'s own rules rather than from taste:
the affordance overlays content, so it needs a safe inset that does not collide with a bottom nav
or a 44pt target at narrow widths; and it cannot be a second `bg-primary` competing with a screen's
own primary action.

### D68. The app owns a settings screen, and the shared layout id is what nearly hid the assistant

D66 and D67 both created a preference and neither had anywhere to live: `nav.settings` pointed at
`magic_starter`'s profile screen, which knows nothing about either. `/ayarlar` is this app's own
settings, and the account settings are one tap further in.

Preferences are stored in magic's local cache rather than on the account. There is no preferences
endpoint yet, and inventing one would mean guessing at a shape the backend has not agreed to. The
local failure mode is also the better one: the worst case is re-picking on a second device, not a
sync that silently loses a choice.

**The assistant launcher is not `bg-primary`.** DESIGN.md allows one primary fill per view and this
floats over EVERY view, including ones whose own primary action is a filled button. A second blue
circle on top of `Stok ekle` would make both look like the main action. Card tone plus a hairline,
the same reasoning that took `Reddet` off ghost.

**The bug worth recording is the shared layout id.** magic merges layouts by id and the FIRST
builder wins (`magic_router.dart`, `_mergeLayouts`). `magic_starter` registers `'app'` before this
app's routes do, so a `layout:` closure written here was collected and then discarded. The launcher
built correctly, threw nothing, logged nothing, and was never in the tree. Two wrong diagnoses came
first, an auth redirect and a `Positioned` inside a scroll view, both plausible and both wrong.

Dropping the id gives these routes their own shell. The cost is that they no longer share a shell
instance with the starter's screens, so shell state rebuilds when crossing between them. Acceptable:
the crossing is rare and the shell holds nothing worth preserving.

### O6. What the first paid tier actually costs in TRY

Turkish price sensitivity is the binding constraint on ARPU and we have no evidence about willingness to pay in this segment. Sortly's 24 USD entry is roughly 1.000 TRY, which is far too high for a Turkish small business.

Assumption until answered: model three price points and test them, and keep the MVP's mistake in mind, where Starter's TRY web price was entered as 9.99 against Plus at 399.99.

### O7. Whether the 2026-07-28 MCP revision migration lands in v1 or later

That revision removed the initialize handshake and the session model. `laravel/mcp` has no support and no stated plan.

Assumption until the ecosystem moves: build on 2025-11-25 semantics, keep the MCP layer thin enough that the transport can be replaced without touching the tools, and carry the migration as a known risk.

### D69. The assistant opens over the screen, not instead of it

D67 makes the assistant reachable everywhere. This decides what "open" means, and the first
implementation got it wrong: the floating button pushed `/asistan`, which replaced whatever the user
was looking at.

That is the wrong shape for what this thing is for. The assistant is meant to be asked about the
product, the count or the shelf in front of you, and a push costs you exactly that context. It also
costs the scroll position, the filter and the row, none of which a route restores.

So the button opens a full-screen modal overlay above the app shell. The screen underneath stays
mounted, closing returns to it unchanged, and there is no state to carry across because nothing was
torn down. On a phone the overlay covers the bottom navigation too, which is what makes it a chat
window rather than a tab, and matches how WhatsApp and ChatGPT treat entering a conversation.

The `/asistan` route stays for the addressable case: a deep link, and the overview's pinned
assistant verb from D66. Same screen, two presentations, differing only in the way out (a back
arrow on the route, a close control in the overlay).

Two implementation facts that are not free and are worth recording, because both cost a debugging
cycle. The overlay has to be mounted OUTSIDE `layout.app` to cover the navigation, and that is
exactly what removes its `Material` ancestor: without one, every string renders in Flutter's yellow
double-underlined fallback, which looks like a theme bug. And the shell wraps each route in a scroll
view, so anything anchored from inside a page anchors to the scrolled content rather than to the
viewport.

### D70. Nothing a screen exists for may sit below an unbounded list

Anılcan found this on the locations screen: the placement automation dial rendered under the
location tree, so any tenant with enough locations to care about automated placement could not reach
the setting that governs it. The shape turned out to be under six screens, and it is a correctness
problem rather than a layout preference. A list that grows without bound has no bottom, so anything
downstream of it is unreachable by construction and no amount of scrolling fixes it.

The remedy depends on what the thing is, and the two cases are genuinely different:

**A setting moves.** It goes to `/ayarlar`, which is where a user looks for a preference anyway, and
the screen that governs it keeps a shortcut ABOVE the list, folded shut, with the current value in
its header. One stored value, two doors. That is what the placement dial did.

**An action gets pinned.** `Sayımı kaydet` belongs to the count in front of you and has nowhere else
to go, so it stays on the screen and stops scrolling instead. `AppPageScaffold`'s `footer:` is that,
and `ui/layouts/page_chrome.dart` explains why it cannot be a `Column` plus `Expanded` here.

Material warns against stacking a bottom action bar with a navigation bar, and the warning is about
a bar of ACTIONS competing with destinations. One primary action with its own summary is the
checkout-bar shape both iOS and Material use, and it reads as belonging to the page. Keep it to one
action and the warning does not apply; add a second and it does.

The same reasoning removed the floating assistant button from on top of that footer. Two viewport-
anchored controls in the bottom-right is two primary actions, which is what Material objects to, so
the host measures the footer and lifts the button by its height rather than letting them overlap.

### D71. One render engine, and the hybrid is the Chrome binary path

D18's reversal says the label sheet is rendered on the backend. This decides with what, and the
constraint that shapes it is that the development machine may have no Docker while the server has it.

**`spatie/browsershot` everywhere.** One Blade template, `->pdf()` for the file and `->screenshot()`
for the preview. Verified current rather than assumed: 5.4.0 on 2026-05-26, MIT, roughly 38.8 million
installs. Reversing D18 means adopting the dependency it was written to avoid, so a dead package
would have made that indefensible.

What differs per environment is the BINARY PATH, not the renderer: Browsershot takes the Chrome and
Node paths as configuration, so local uses the machine's own Chrome and the server uses the image's.
The MVP already did this and it is the one piece of its label code worth copying verbatim.

**A driver per environment was considered and rejected.** `spatie/laravel-pdf` would let local run
Browsershot and the server run Gotenberg, which is genuinely attractive: no Node in the PHP image and
a simpler Octane memory profile. Both engines even cover both outputs (Gotenberg 8 has
`/forms/chromium/screenshot/html`, checked). It is still wrong here, because two engines render
subtly differently and this feature is judged on whether a sticker lands on a die-cut. The thing
tested locally has to be the thing that prints.

The debt this leaves is stated rather than hidden: Node and Puppeteer must exist on a development
machine, and Chrome's process lifecycle inside a long-lived Octane worker needs attention.

**Fonts are embedded in the template as base64, and asserted by a test.** Only fonts available to the
renderer can be used, and a laptop and a container never have the same set. `DESIGN.md` requires
`latin-ext` for `Ğ ğ İ Ş ş` and records that its absence looks like a fallback glitch rather than a
missing glyph; on a label that failure is printed onto adhesive paper and stuck to a shelf. Embedding
makes the bytes identical everywhere and survives a change of engine. The test exists because font
provisioning fails silently: render a label carrying all five letters, extract the text, assert it
matches with no tofu. That needs `pdftotext` in CI, which is what makes the guarantee real rather
than intended.

**Delivery is synchronous, and the preview is cached under a hash of the template plus its data.**
A sheet is a handful of pages; a queue and a notification for 24 labels is ceremony nobody asked for.
The cache is what makes a preview affordable, and changing a template or a field produces a new key
rather than a stale image. The threshold where a job belongs on the queue is real and is not v1's
problem.

### D72. PostgreSQL everywhere, including the test suite

Dev, CI and production run PostgreSQL. Tests move off SQLite `:memory:`.

The reason is measured rather than stylistic. `products`' own migration already records the cost of
the split: *"Partial uniqueness (only where `sku` is not null) is not portable to sqlite, which the
test suite runs on, so the pairing is indexed here"*. So `(team_id, sku)` uniqueness is enforced
NOWHERE today, and the test that would have caught that ran green on a database which cannot express
the constraint.

The schema this documentation set specifies leans much harder on Postgres than one partial index:
native `uuid`, `jsonb`, `pg_trgm`, pgvector, exclusion constraints. Every one of those is a place
where a SQLite-green suite would be certifying a schema it never built.

A second, independent argument surfaced while measuring the UUID flip. `User` uses
`ConditionallyUsesUuids` while Laravel's own `create_users_table` hardcodes `$table->id()`, so with
uuids enabled the model inserts a string into a bigint column. PostgreSQL rejects that outright;
SQLite is dynamically typed and would have stored it. The failure mode SQLite hides is exactly the
class this schema is full of.

Cost, accepted: the suite is slower than in-memory, CI gains a Postgres service container, and the
image has to be `pgvector/pgvector` so the vector columns are testable rather than skipped.

### D73. UUIDv7 primary keys, overriding the starter's ordered UUID

`magic-starter.use_uuids = true`, and `ConditionallyUsesUuids`' generator is overridden from
`Str::orderedUuid()` to `Str::uuid7()`. The same correction goes upstream as a PR rather than living
here forever.

Both are time-ordered, so B-tree locality is not the differentiator; the format is. `orderedUuid()`
is a COMB: a v4 built through `TimestampFirstCombCodec`, sortable but declaring version 4. `uuid7()`
is RFC 9562, which Postgres 18 generates natively, every tool recognises, and Laravel 13's own
`HasUuids` already returns. Leaving the starter's generator in place would mean any package reaching
for `HasUuids` writes a second, different UUID flavour into the same schema.

PostgreSQL is what makes the choice cheap: verified in `PostgresGrammar::typeUuid()`, a `uuid` column
is the native 16-byte type, where MySQL would emit `char(36)`. That saving repeats on every foreign
key in a schema where almost every table carries two or three.

Rejected: a bigint key with a separate uuid public id. It is the smaller index and the faster join,
and it is wrong here for a security reason rather than a performance one. Ids travel through MCP tool
arguments and assistant tool calls, and `data-model.md`'s rule that a cross-tenant read returns 404
rather than 403 exists precisely so identifiers cannot be enumerated. Two identifiers per row means
the enumerable one eventually leaks into a place that assumed the other.

Known cost, bounded: Laravel's `create_users_table` hardcodes integers in two places (`users.id` via
`$table->id()`, and `sessions.user_id` via `foreignId`), so it has to be made uuid-aware. The
starter's own 13 migrations already route through `MigrationHelper` and need nothing.

### D74. Meilisearch owns user-facing search; PostgreSQL owns the resolution cascade

Two searches that look alike and are not. What a user types into `/ara` wants typo tolerance,
instant results and ranking across products AND locations: that is Meilisearch's job, through
`laravel/scout`. What the receipt pipeline does to `PNR SUT 1LT` is a resolution cascade whose first
two steps are an exact-and-normalised match against the tenant's own products and then embedding
similarity: that is Postgres' job, in the same transaction as the write.

Consequence for the schema, and it is a subtraction: **no `tsvector` column anywhere.** Stemmed
full-text belongs to Meilisearch; Postgres carries a normalised-name column with a `pg_trgm` index
(trigram is what actually matches a truncated receipt line) plus the vector column from D75.

Worth recording because it corrects a research error made while deciding this. PostgreSQL DOES ship
Turkish full-text search: `pg_catalog.turkish` and `turkish_stem` are both in the PG 18 catalogue, so
the argument that Turkish forces an external engine is false. Meilisearch is chosen on typo tolerance
and instant ranking, which are real, not on a stemmer gap that does not exist.

Rejected: routing the cascade through Meilisearch too. It would make receipt ingestion depend on a
service outside the transaction, so Meilisearch being down would stop capture rather than degrade
search.

### D75. pgvector is self-hosted, embeddings come from OpenRouter, one column per table

The vector STORE is ours: pgvector in our own Postgres. The vectors are PRODUCED by
`google/gemini-embedding-001` through OpenRouter at 1536 dimensions, which `laravel/ai`'s
`OpenRouterProvider` already carries as its embeddings default.

`vector(1536)` costs `4 * 1536 + 8` = 6,152 bytes per row and sits comfortably under pgvector's
2,000-dimension HNSW ceiling. `halfvec` would halve that and remains available if index size ever
becomes the binding constraint.

**The column type fixes the dimension, so this decision is expensive to reverse**: moving to a
1024-dimension model later means a new column and re-embedding the whole catalog. That is the reason
it is taken before the first migration rather than during.

The column lives on each table that can be searched: `products`, `global_products`, `off_products`,
each with its own HNSW index. This matches the cascade's own shape, which queries the cheapest and
most trustworthy source first and stops on a hit, so separate queries are the design rather than a
compromise.

Rejected: one shared `embeddings` table with a morph. It buys a single index and one query, and it
costs the thing this schema is most careful about: tenant-owned and global rows would share a table
with a nullable `team_id`, so half the rows would legitimately have no tenant and every query would
carry the burden of proving it filtered correctly. Filtered vector search also loses recall in
pgvector, which `hnsw.iterative_scan` mitigates and does not remove.

Consequence for KVKK: product names cross the border to reach the embedding model, so the gateway's
redaction step applies to the embeddings path exactly as it does to the vision paths. A fully
self-hosted embedding model through `laravel/ai`'s `openai-compatible` driver remains the escape
hatch if counsel's answer to O3 requires it, and the dimension would have to be matched.

### D76. OpenRouter is one provider among several, not the only path

The AI provider is OpenRouter, and the design must not assume it. A category's model list is an
ordered list of `(provider, model)` pairs rather than bare model identifiers, so a second provider
can be added to a category without reshaping anything.

This is Anılcan's call and it earns its cost. `laravel/ai` ships first-class support for OpenRouter
alongside OpenAI, Anthropic, Gemini, Azure, Bedrock, Groq, xAI, DeepSeek, Mistral and Ollama, plus an
`openai-compatible` driver for anything else, and its native failover is expressed as a list of
PROVIDERS. Storing bare model strings would throw that away and would tie every category to one
vendor's outage.

The categories are already written: `ai-design.md`'s five gateways, each with a stated weighting
(receipt extraction weights accuracy, product recognition weights cost, text normalisation wants
small and fast, placement explanation defaults to a template rather than a model at all, the
assistant wants the strongest tool-calling), plus a sixth the document did not name because it had no
gateway: embeddings.

### D77. Model fallback is layered, because two different things fail

Three model-level fallback mechanisms exist and they are not interchangeable, so two of them are used
at once for different failures.

**OpenRouter's `models` array handles infrastructure.** Verified from its own documentation: an
ordered array in the request body, falling back on context-length errors, moderation flags,
rate-limiting and downtime, resolved inside one HTTP call. Two details matter downstream: the request
is priced at the model that actually served it, and that model is returned in the response's `model`
attribute, so usage accounting must read the response rather than the request.

**Our gateway handles semantics.** `ai-design.md` already specifies a fallback trigger OpenRouter
cannot see: a malformed structured response is retried once with a stricter instruction, then falls
back to the manual path. A model returning HTTP 200 with JSON that fails our schema is a successful
request as far as OpenRouter is concerned. So the gateway loops the category's `(provider, model)`
list itself, which is also what lets it write one usage row per attempt and cross a provider boundary
rather than only a model one.

Rejected: OpenRouter presets (`@preset/slug`). Storing the chain server-side at OpenRouter is
operationally attractive because a model swaps without a deploy, and it moves the configuration out
of git, which is exactly what `ai-design.md`'s "model identifiers are configuration, never literals"
rule exists to keep auditable.

### D78. `ai_usage_events` records one row per attempt, grouped by action

Fallback makes this a real schema question rather than a naming one: one logical AI action can now
produce two or three model calls, and OpenRouter bills whichever answered.

So each model call is a row carrying its provider, its model, its token counts, its computed cost and
its outcome, plus a shared action identifier and an attempt ordinal. Credit is deducted per ACTION;
cost is accounted per ATTEMPT.

`monetization.md` demands three answers (what does this tenant cost us, is the credit price above our
marginal cost, which feature is consuming the budget), and a first model that quietly fails and hands
off to a second is invisible to all three unless the attempt is the row. A failed attempt can also
still be billed, since a context-length rejection consumes tokens.

Rejected: a separate `ai_actions` table. It is the cleaner normalisation and it is two tables where
one carries both questions today; `monetization.md`'s own record of the MVP rewriting its plan schema
five times argues for the smaller shape until the second table has a question of its own.

### D79. `stock_movements` is not partitioned yet, and is shaped so that it can be

Retention is a pricing axis (D4) and `monetization.md` promises that history beyond the window
becomes unqueryable rather than deleted, which is exactly what detaching a partition does. So
partitioning is the eventual answer and it is not the v1 answer.

What decides the timing is a constraint quoted from the PostgreSQL 18 documentation: *"the
constraint's columns must include all of the partition key columns"*. Partitioning by `occurred_at`
therefore forces the primary key to `(id, occurred_at)`, which Eloquent's single-key model does not
express, so `find()` and every relation would need hand-holding from day one on a table with no
scale problem yet.

The table is instead designed so the migration stays cheap: `occurred_at` is NOT NULL and is never
updated (which the append-only ledger already guarantees rather than merely promises), and every
index leads with `team_id` and `occurred_at`.

Cost stated rather than hidden: converting later is a table rewrite, and by then the table will hold
the rows that made it necessary.

Rejected: hash partitioning on `team_id`. Pruning would work on every query since every query is
already tenant-filtered, and it would push tenant isolation down to storage, both real. It does not
help the thing that actually needs solving, because retention is a time axis, and it costs the same
composite primary key.

### D80. The ledger's foreign keys restrict; only the tenant cascades

`stock_movements.product_id`, `.location_id` and `.stock_lot_id` are `restrictOnDelete`. `team_id`
stays `cascadeOnDelete`.

The migrations shipped all three as `cascadeOnDelete`, which quietly contradicted invariant 4
("`stock_movements` rows are never updated or deleted"). Enforcing that at the model level while
instructing the database to cascade leaves every path that bypasses the model holding the knife: a
force delete, a cascade arriving from somewhere else, a bulk action in the Filament panel D19 brings,
a `DELETE` in tinker. A property an append-only ledger only has by convention is not a property.

`products` and `locations` already soft-delete, and soft delete has nothing to do with a foreign key,
which is why this needed fixing separately: the constraint governs the force path, and the force path
is the one that loses history.

The tenant cascade is deliberate and stays. `legal-and-privacy.md` requires account and tenant
deletion that actually deletes, so a team's rows going with it is the feature.

Consequence, accepted: deletion order now matters and runs innermost-first, and the account-deletion
path needs a test that proves it completes rather than tripping over its own restrictions.

Rejected: nulling the foreign key and denormalising a name snapshot onto each movement. It keeps the
ledger readable after a product is gone, which is what an audit log wants, and it gives invariant 1
("for every (product, location), the materialised balance equals the sum of ledger deltas") nothing to
mean on the rows whose product is null.

### D81. `product_stock` is maintained by the application, not by a trigger

`app/Services/StockWriter` writes the movement and updates `product_stock` and
`stock_lots.remaining_quantity` inside one transaction. Anılcan's call, against the recommendation
here, and the cost is what has to be paid rather than argued away.

What the alternative offered: a database trigger makes invariant 1 structurally true, because no path
can append a movement without moving the projection, whichever surface wrote it. What it costs is that
the arithmetic lives in SQL, invisible to Eloquent and to a PHP test, and a model that has just
written a row reads a stale projection until it refreshes.

Two things follow from choosing the service, and they are obligations rather than notes:

1. **Every write path goes through `StockWriter`, without exception.** The service is now the
   invariant, so a movement inserted anywhere else silently desynchronises the balance. That includes
   seeders, factories, the MCP write tools in v2, the assistant's tools, and anything Filament grows.
   A test asserting no other code path inserts into `stock_movements` is worth more here than it would
   be with a trigger.
2. **The scheduled consistency check is mandatory, not a safety net.** `data-model.md` already
   describes it ("compares it against the ledger and reports drift; the ledger always wins"), and with
   the trigger it would have been belt-and-braces. Here it is the only thing that catches the failure
   this design permits, so it ships with the feature rather than after it.

### D82. Normalisation folds every diacritic, including ı to i

> **The MECHANISM here was superseded by D84 the same day.** The fold and its reasoning stand
> unchanged; what changed is where it runs. This decision specified a generated column calling
> an IMMUTABLE `unaccent` wrapper, and D84 removed database-side computation entirely, so the
> fold is `Str::lower(Str::ascii($name))` in PHP, written by a mutator and guarded by a test
> (D88). The `unaccent` extension is no longer installed. The PostgreSQL gotcha described at the
> end of this decision is therefore no longer live, and is kept because it is the reason the
> mechanism could not simply be moved.

`name_normalized` is `lower()` plus `unaccent()`: `ı→i`, `ş→s`, `ğ→g`, `ü→u`, `ö→o`, `ç→c`. Indexed
with `pg_trgm` and used for the resolution cascade's first step.

Turkish makes this a genuine tension rather than a default. The i/ı distinction is real and semantic,
and folding it means `kirmizi` and `kırmızı` become the same key. That is accepted because this column
is a MATCHING key and never a displayed value: `name` keeps the original, and the failure this trades
away is worse. A user without a Turkish keyboard, a user in a hurry, and a thermal receipt that prints
no diacritics at all are the three inputs the cascade most has to work on, and a conservative fold
loses all three.

Rejected: no fold at all, leaning on trigram similarity. It removes the `unaccent` dependency and it
fails hardest exactly where it matters, because `süt` against `sut` is one character in a
three-character word and trigram similarity is weakest on short strings. The most common products have
the shortest names.

The PostgreSQL gotcha and its standard answer: `unaccent()` is not marked IMMUTABLE (its dictionary can
be changed), while both generated columns and index expressions require IMMUTABLE. The community
answer, which is what this uses, is a thin wrapper function declared IMMUTABLE. It is a promise to
Postgres that the dictionary will not change under it, so changing the `unaccent` rules means
reindexing, and that is worth a comment at the definition site.

### D83. The embedding is written on a queue, and the column is nullable

`products.name_embedding` is nullable. A Horizon job fills it after the row is saved.

`product.md`'s first success criterion is ten items into stock in under five minutes without reading
anything, and making every product save wait on an outbound HTTP call collides with it directly. The
cascade is already layered, so a product with no embedding is still found by step one (the normalised
match) and simply does not take part in step two.

The stronger reason is monetization: `monetization.md` promises that at the limit every AI path
degrades to its manual equivalent. A NOT NULL embedding column makes product creation itself depend on
an AI call, so a tenant out of credits could not add a product at all, which is the dead-end 403 D4
exists to prevent.

Consequence, and it needs somewhere to be visible: "a product without an embedding" is a legitimate
temporary state, so a stalled queue is invisible unless something measures it. `name_embedding IS NULL`
older than a threshold is the query, and it belongs on the Filament panel rather than in someone's
memory.

Rejected: a separate `embedding_status` enum plus `embedded_at`. It makes a permanent failure legible,
and `name_embedding IS NULL` already answers most of the same question without a second state machine
to keep honest.

### D84. No database functions, no stored procedures, no generated columns

Computation lives in Laravel. PostgreSQL stores, indexes and constrains; it does not calculate.
Anılcan's constraint, and it arrived after a `depools_normalize(text)` wrapper had already shipped,
so this decision is also the record of removing one.

The reasoning it overrides was real and is worth keeping visible, because it is what the constraint
trades away. A generated column CANNOT disagree with the column it derives from: `name_normalized`
computed by the database is correct by construction, whichever code path wrote `name`. A wrapper
function was the only way to get there, because both generated columns and index expressions require
IMMUTABLE and `unaccent()` does not promise it.

What the constraint buys is smaller and easier to reason about, and it is not nothing:

- The `unaccent` extension is no longer needed at all. Postgres indexes a value PHP already wrote, so
  only `vector` and `pg_trgm` remain, and the schema has zero application-owned functions (verified:
  the 149 functions in `public` are all extension-owned, 118 from vector and 31 from pg_trgm).
- No IMMUTABLE promise to break. The wrapper's honest cost was that changing the transliteration
  rules silently invalidates every index built on it, fixable only by REINDEX and warned about by
  nothing.
- One language holds the logic, so a normalisation rule is read, tested and changed in one place.

What it costs is drift, and the cost is paid where the value is written rather than argued away here.
See D88.

Consequence for the rest of the schema, stated once so it is not re-decided per table: a derived
value is either written by PHP with a guard, or not stored at all and computed at the boundary. There
is no third option now, and "add a trigger" is not available as a fix later.

### D85. GTIN-14 is the canonical barcode identity; symbology is metadata

`barcodes.gtin` is `CHAR(14)`, left-padded with zeros, and unique. `symbology` records how the code
was READ and is no longer part of the identity.

The shipped schema had it wrong, and GS1's own text says so: *"GS1 recommends that GTIN is always
stored as a 14-digit number in the data bases. Shorter formats should be filled in with leading
zeroes up to 14 characters."* GS1 Canada repeats it. With uniqueness on `(code, symbology)`, one
physical product read as UPC-A `012345678905`, as EAN-13 `0012345678905` and from a case label as
ITF-14 `10012345678902` becomes three rows and catalogues the same yoghurt three times.
`data-model.md` had recorded the shallow version of this bug (the MVP's nullable symbology produced
two rows); the deep version is that the pair was the identity at all.

`CHAR(14)` and never an integer, because leading zeros are significant: storing `0614141999996` as a
number drops one and the lookup fails against the padded form a scanner returns.

Fourteen rather than thirteen for a product reason as well as a standards one: D25's `koli` is a real
purchase unit, so a delivery arrives with ITF-14 case labels, and a 13-digit field cannot hold the
indicator digit that makes a case code a case code.

**Non-GTIN codes are first-class, not an afterthought.** A Code128 internal label (which
`labeling-and-printing.md` requires so an internal code can never be mistaken for a manufacturer
EAN-13), a QR and a DataMatrix have no GTIN. Those rows carry `gtin = NULL` and are identified by
`(code, symbology)` instead. PostgreSQL's partial unique indexes let both identity regimes live in
one table cleanly, which is a second thing the SQLite suite could not have expressed (D72).

### D86. Open Food Facts normalises to 13 digits, so the bridge is a PHP value object

OFF's own reference documents rules that CONFLICT with GS1: barcodes of 7 digits or fewer are padded
to 8, barcodes of 9 to 12 digits are padded to 13, 8-digit codes stay at 8, and EAN-14 is not
addressed. So OFF's canonical form is 13 (or 8) where ours is 14, and a naive join between
`off_products` and `barcodes` silently misses.

`off_products` is our table, so it is keyed on GTIN-14 like everything else and every internal join
stays in one format. The conversion is a PHP value object called only at the OFF boundary, since D84
rules out doing it in the database.

**OFF's own code is stored as `source_ref`, and that is provenance rather than a derived mirror.**
`legal-and-privacy.md` already requires per-row provenance so a takedown can be executed precisely,
and for an OFF row the natural pointer back to the origin IS its OFF code. One column answers both
needs, and nothing derived is duplicated.

Rejected: a second indexed `off_code` column. It is a stored derived value, so it carries exactly the
drift risk D88 is about, and here the alternative is free because the conversion is deterministic.

### D87. `product_categories` keeps our own key and Google's as a stable foreign one

`uuid` primary key like every other table, plus `google_id INTEGER NULL UNIQUE` as the external key,
plus `name_tr` and `name_en`, plus a materialised `path` and `depth`.

The taxonomy file was downloaded and measured rather than assumed: `taxonomy-with-ids.tr-TR.txt`
returns HTTP 200 at 579 KB, holds **5,596 nodes** in the shape `5608 - Bavullar ve Çantalar >
Alışveriş Çantaları`, and nests **7 levels** deep. The Turkish translations are real and idiomatic
(`Bebek Devam Sütleri`, `Anne Sütü Depolama Kapları`), which was the thing most worth checking.

Two facts from the file changed the design. Its first line is
`# Google_Product_Taxonomy_Version: 2021-09-21`, so the taxonomy has been **frozen since September
2021**: no churn to absorb, and a seed that will not shift underneath us. And the sources are
consistent that when Google renames a node the numeric ID keeps resolving while the text path stops,
so **the ID is the stable key and the path is only a label.**

`google_id` is nullable because two legitimate kinds of row do not have one: a tenant's own category
(`data-model.md` allows those, carrying a `team_id`) and anything mapped in from OFF.

Rejected: using Google's numeric ID as the primary key. It is the most direct mapping and it would
make this the only table in the schema not keyed by uuid, and an exception to a uniform rule is
exactly what gets forgotten. It also cannot key the tenant and OFF rows at all.

Rejected: a separate translations table. Correct normalisation, and v1 has two locales, so it buys a
join on every category read in exchange for flexibility whose payoff has no date on it.

### D88. `name_normalized` is written by a mutator and guarded by a test

The column is written by an attribute mutator on `name`, so the two values are set in one assignment
and `create`, `update`, `fill` and `firstOrCreate` are all covered without anyone remembering.

The fold is `Str::lower(Str::ascii($name))`, chosen by measurement rather than by reputation:

| | Result for `Pınar Süt 1 LT — ÇĞİİŞÖÜ çğıişöü` |
|---|---|
| `Str::ascii()` | `Pinar Sut 1 LT - CGIISOU cgiisou` — all six Turkish diacritics folded |
| `Transliterator` (intl) | identical |
| `iconv('ASCII//TRANSLIT')` | `Pinar S"ut 1 L- c ?GIS^csC?gis_cs` |
| `mb_strtolower` alone | folds nothing, and turns `İ` into `i` plus a combining dot |

`iconv` is the one worth naming: it is the obvious reach, it is locale-dependent, and it produces
garbage here. Testing it was the difference between a working cascade and a silently broken one.

**The mutator is not airtight and the gap is named rather than implied.** `Product::query()->update(['name' => ...])`
bypasses mutators AND observers, so a mass update leaves the normalised value stale and the cascade
misses a product that looks present. A test recomputes the fold for every row and compares it against
the stored column, so drift surfaces on the next suite run instead of as a resolution failure months
later. This is the same shape as D81: the application owns an invariant the database used to be able
to own, so the check that catches its failure ships with it.

Rejected: an observer. It handles several fields in one place, and it can be switched off
(`withoutEvents()`, a seeder), which leaves the column silently empty. A mutator cannot be switched
off.

### D89. Confirmed receipt aliases are a table, in two layers

`ai-design.md` promised that "every resolution the user confirms strengthens step 1 for next time" and
named no mechanism. `receipt_lines` holds per-receipt state, so without a table the promise is empty:
the next receipt runs the whole cascade again and pays for step 3 again.

Measuring the cascade is what made this concrete rather than theoretical. `PNR SUT 1LT` is the case
trigram cannot solve (D82's measurement: the right product scores 0.233 against a wrong one at 0.333,
below the 0.3 threshold, so it is not even returned). A confirmed alias turns that from a model call
into an exact match, permanently, at zero cost.

Two tables:

- `product_aliases(team_id, alias_normalized, product_id, ...)` points at the tenant's own product and
  works from the second receipt onward.
- `global_product_aliases(alias_normalized, global_product_id, confirmed_count)` receives only the
  confirmations that pointed at a SHARED catalog entry, under the same per-tenant opt-in the community
  catalog uses, and subject to whatever O5's terms settle.

The shared layer is where D11's thesis actually lives. A receipt abbreviation is a property of a
BRAND and a printer, not of a tenant, so `PNR` means Pınar for everyone in Turkey. That makes it the
single most shareable thing this product collects, and no global competitor has a reason to collect
it.

Rejected: tenant-scoped only. It resolves the second receipt for one tenant and leaves every new
tenant relearning `PNR SUT 1LT` from scratch while paying for step 3, which is handing back the
advantage D11 exists to build.

### D90. The ledger records the unit the user entered, beside the base quantity

`stock_movements` gains `entered_quantity` and `entered_unit`. `delta` stays in the base unit and all
balance arithmetic stays on it.

D25 already avoids SAP's failure (a factor change silently re-deriving historical quantities), because
storing `delta` in base units means history cannot be reinterpreted. What was left unsolved is
DISPLAY: `inventory-core.md` says display may use whichever unit the user last used, and without a
record of what was entered, a delivery keyed as "2 koli" shows as "24 adet" forever.

That matters more than it sounds because `MovementRow` renders on three surfaces (a product's history,
the activity panel, the assistant transcript). A user who does not recognise their own entry stops
trusting the ledger, and the ledger is the thing this product is built on.

Storing the entered text also means a later factor change cannot corrupt the display either: "2 koli"
is a recorded fact rather than a division performed at read time.

Cost: two columns, and a test that `entered_quantity × factor` reconciles with `delta` at the moment
of writing, so a conversion bug is caught where it happens rather than as a balance that drifts.

### D91. Embeddings go through the gateway and do not consume a credit

The embeddings gateway runs redaction and writes its `ai_usage_events` row like every other gateway,
and it does NOT check the credit balance.

The arithmetic settles it. `gemini-embedding-001` is $0.15 per million input tokens and a product name
is roughly 20 tokens, so one embedding costs about $0.000003 and embedding a 2,500-SKU tenant's entire
catalog costs under one cent. Against O2's working assumption of $0.05 to $0.10 per credit, one credit
is around 20,000 product embeddings. Metering that is accounting for noise.

The stronger reason is behavioural. `monetization.md` promises that at the limit everything existing
keeps working and only the metered action stops, and D83 already made product creation independent of
an AI call for exactly that reason. A credit check here would mean a tenant out of credits keeps
adding products whose embeddings never arrive, so the cascade's second step quietly dies for them and
receipt resolution degrades at the precise moment they are least able to fix it. The blocked cost
would be three millionths of a dollar.

Usage is still recorded, so `monetization.md`'s three questions (what does this tenant cost us, is the
credit price above marginal cost, which feature eats the budget) all stay answerable.

Rejected: skipping the gateway. Redaction lives inside it and product names cross the border, so that
would leave the one path KVKK most requires auditing unaudited.

### D92. Affinity carries `last_placed_at`, because `updated_at` moves on a decrement too

`location_category_affinity` gets `count`, `updated_at` and a separate `last_placed_at` written only on
the INCREMENT.

`data-model.md` specified `count` plus `updated_at`, and D9's third fallback is "most recently used
location". Those two facts together are a bug: a correction decrements the rejected location's count,
which touches its `updated_at`, so ordering by `updated_at` to find the most recently used location
points at the place the user just refused. The failure surfaces as a wrong suggestion, which is the
hardest kind to diagnose because nothing is broken.

One extra column, written in one branch, and the recency signal stays honest.

The floor at zero stays as D9 wrote it. A signed count that goes negative would punish a repeatedly
rejected location more effectively and would cost the property that makes this model worth having:
the count IS the explanation shown to the user ("bu çekmecede zaten 3 tane var"), and a negative
number explains nothing.
