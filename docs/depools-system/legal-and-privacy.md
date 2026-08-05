# Legal and privacy

Obligations, data-source licensing, and the risks accepted on purpose. This document exists so nobody has to reconstruct why an architectural constraint is there.

Nothing here is legal advice. It records what the sources actually say, quoted, so counsel can be asked a precise question rather than a vague one.

## KVKK: the constraint that shapes the architecture

Depools.ai is Turkey-first and processes photographs of homes and businesses, receipts, and free-text messages. Two Turkish requirements shape the build.

### Cross-border transfer applies to every AI call

Sending personal data to a model hosted outside Turkey is a cross-border transfer under KVKK Article 9. Under the post-2024 regime (Law 7499) this requires an adequacy decision, a Kurul-approved standard contract, or binding corporate rules. Open-ended explicit consent became an exceptional mechanism rather than the primary one.

This is not confined to the email feature. Every one of these crosses the border the moment it reaches a non-Turkish model:

- A receipt photograph, which may include a customer's name or card digits.
- A product photograph, which may incidentally include a person.
- A free-text note on a stock movement.
- An assistant message, which is whatever the user chose to type.
- An email body forwarded for parsing.

Architectural consequences, all v1:

1. **A redaction step runs before any content reaches a model.** Strip and mask what does not need to leave: card fragments, national identifiers, phone numbers, email addresses, and free-text fields the feature does not require.
2. **Model provider selection weighs data residency**, rather than treating it as a tiebreaker.
3. **Purpose-scoped consent is recorded per feature**, with a version and a timestamp, so it can be shown that consent for receipt parsing was not silently reused for email ingestion.
4. **No training on tenant content.** We do not fine-tune on customer data, and provider terms are chosen accordingly. This is also a marketing position nobody in the category currently claims (see `market.md`).

### Consent must be two documents, not one checkbox

The Kurul's decision 2026/347 of 2026-02-18 requires the aydınlatma metni (privacy notice) and the açık rıza metni (explicit consent) to be prepared as separate documents. A single bundled "okudum, kabul ediyorum" checkbox covering both is no longer valid.

The onboarding flow is built this way from the start, because retrofitting a consent model after users exist means re-consenting everyone.

### Special category data

KVKK Article 6 special categories (health, biometric, union membership) can appear incidentally in a scanned invoice or a note. Guidance is that such data should not be entered into AI tools at all, or should carry substantially stronger safeguards. The redaction step above is the mitigation, plus a documented position that the product does not solicit this data.

KVKK's own generative-AI guidance published in November 2025 confirms this is an active regulatory focus rather than a dormant rule.

### One obligation that is not a feature

KVKK requires every data controller to maintain a Kişisel Veri İşleme Envanteri. That is an obligation on the company, not something to build into the product. Noted so it is not confused with a feature request.

## GDPR

If the product serves EU users, the lawful basis is contract performance (Article 6(1)(b)) or legitimate interest (Article 6(1)(f)) rather than consent, because consent must be freely given and a user who needs the feature is not free to refuse it.

Any model provider is a processor and needs an Article 28 data processing agreement covering scope, sub-processors, retention and breach notification. A provider outside the EU additionally needs standard contractual clauses and a transfer impact assessment.

## Product data source licensing

The layered resolution order from D11, with the licence position for each layer.

### GS1 Verified by GS1: query only, never cache

**We do not store GS1 content.** Verified by reading the terms directly. Three clauses decide it:

Clause 19.1, on permitted use: "You may use the Content solely within your business and for your own business processes, excluding any commercial use ('commercial use' meaning any use where the Content is sold, leased, licensed or otherwise made available as a whole or in part, on its own or as part of another product/service). You shall not share, release, submit or allow extraction of the Content by any party other than your own employees or agents."

On permanent copies, among the prohibitions: "create permanent copies of the Content except to the extent permitted by these Terms of Use".

Clause 8, which makes the permission list closed rather than open: "If these Terms of Use do not specifically say that You can do something in connection with the User Interface or the VBG Service than you cannot."

A shared catalog serving paying subscribers is content "made available... as part of another product/service", and storing it is a permanent copy. Two clauses breached at once. The "Value-Added Product" carve-out does not rescue it, because it states that "Replicating the Content and/or the Service shall not be considered as adding appreciable value".

There is also an operational limit: no more than 500 GTINs per request. And on termination, clause 55 requires deleting all copies of the content, which is only survivable if there are no copies.

GS1 may therefore be used for live validation of a barcode's structure and ownership at the moment of a scan. Nothing is written to `global_products`.

### Open Food Facts: usable, but isolated

Data is ODbL, photographs are CC-BY-SA 3.0. Those are two different licences on the same record, which is easy to get wrong.

The clause that drives our schema: "If you combine data from Open Food Facts with other databases, then the ODbL requires that the resulting database must be released as open data as well."

So OFF-derived rows live in their own table (`off_products`), never merged row-for-row into `global_products`. Isolation keeps the share-alike obligation contained to data that is already open, rather than letting it reach across our proprietary catalog. Attribution is displayed wherever an OFF-sourced field is shown.

### Paid lookups

Commercial APIs on ordinary commercial terms. Cache according to what each provider's terms permit, recorded per provider in the implementation.

### Scraping: a risk accepted on purpose

Retained as a last-resort fallback at Anılcan's explicit direction, after the risk below was raised and reaffirmed. Recording it here is the condition of retaining it.

**The risk.** Post-*hiQ* case law does not make scraping settled-illegal, but it also does not clear it. The Ninth Circuit's CFAA holding in *hiQ Labs v. LinkedIn* did not reach trespass to chattels, copyright, misappropriation, unjust enrichment, conversion or breach of contract, and the case settled with hiQ paying damages and destroying the scraped data. *Meta v. Bright Data* (2024) and *X Corp v. Bright Data* (2024) were both narrow and the latter is on appeal.

The sharper exposure is the EU sui generis database right, which is assessed by volume and by the strategic value of what is taken. Building a cross-tenant catalog from many retailers' full listings is architecturally the "bulk download the catalog" pattern that doctrine targets, independent of any CFAA question, and independent of the site's terms of service.

Practically it is also a diligence problem: an investor or acquirer reviewing the data pipeline will find it.

**The constraints that contain it.** Scraping is permitted in v1 only under all of these:

1. Results are written to the requesting tenant's own products, never to the shared community catalog. The cross-tenant redistribution that creates the database-right exposure does not happen.
2. Each source is a separately configurable adapter with an independent kill switch, so a single source can be disabled within minutes without a deploy.
3. It runs only after every other layer has missed, so volume stays low by construction.
4. `robots.txt` is respected, requests are rate-limited and identified, and no authentication wall is crossed.
5. Provenance is recorded per row (`source = scraped`, plus `source_ref`), so a takedown can be executed precisely.
6. Confidence is set low on scraped rows, so they are presented to the user as unverified rather than authoritative.

**The review trigger.** If scraping volume grows beyond an incidental fallback, or if any source objects, the feature is disabled rather than defended.

## Turkish invoice data

e-Arşiv and e-Fatura documents belong to the user, who is a party to them. We process them on the user's instruction to extract what they bought.

The KVKK Board has penalised accidental exposure of invoices to the wrong recipient (decision 2022/325), which implies the obligation is on verification and access control rather than on processing being prohibited. So: the inbound address is unguessable, sender addresses are verified (SPF, DKIM, DMARC) and allowlisted per tenant, and an invoice that fails verification is rejected rather than filed.

Programmatic access to GİB records is only available through authorised integrators on B2B terms. There is no consumer-consent API. We therefore never query GİB on a user's behalf; we process only what the user sends us.

## Data subject rights

Both KVKK and GDPR require these, and they are v1:

- **Export.** Everything the tenant owns, in a machine-readable format: products, locations, the full movement ledger, lots, receipts, and uploaded images.
- **Deletion.** Account and tenant deletion that actually deletes, including images in object storage and derived rows. Contributed community-catalog entries are anonymised rather than removed, which the contribution terms must state plainly up front.
- **Correction.** Already inherent in the ledger: a wrong movement is corrected by a compensating entry with reason `correction`, so the record stays truthful about what happened and when it was fixed.

The MVP had no export path at all.

## Security posture relevant to legal exposure

Three items where a security failure becomes a legal event:

1. **Tenant isolation.** Cross-tenant leakage is a reportable data breach under both regimes. The Asana MCP incident leaked across roughly 1,000 organisations and went unnoticed for over a month. Isolation tests precede features (see `data-model.md`).
2. **Untrusted content reaching a model.** A product name, a supplier note or a scraped description can carry injected instructions. All tool output is treated as untrusted data, never as instruction, and authorisation is enforced server-side rather than by prompt wording.
3. **Image storage.** Photographs of homes and businesses are personal data. Private buckets, signed short-lived URLs, no public paths, and retention that ends when the tenant deletes.
