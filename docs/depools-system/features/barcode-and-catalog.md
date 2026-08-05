# Feature: barcode scanning and the product catalog

> Summary depth. Deepens after the design mockups settle the interaction decisions.

Scan a barcode, get a product. Build a Turkish product catalog nobody else has, without breaking anyone's licence.

Decision D11 in `open-decisions.md`. Licence positions in `legal-and-privacy.md`.

## Scanning

`mobile_scanner` on all three platforms. It supports web through three selectable backends, unlike the ML Kit package which is Android and iOS only, and it carries roughly nine times the adoption.

Symbologies: EAN-13, EAN-8, UPC-A, UPC-E, Code128, Code39, QR, DataMatrix.

The MVP's scanner never worked. The camera widget was commented out in `barcode_scanner.dart` and only manual entry functioned. Continuous scanning matters here: unpacking a delivery means scanning twenty things in a row, so the scanner stays open and accumulates rather than closing after each hit.

## The resolution cascade

Cheapest and most trustworthy first.

```
1. tenant's own products          free, instant, most common case
        │ miss
2. community catalog              free, opt-in contributions from our users
        │ miss
3. off_products (Open Food Facts) free, ODbL, isolated table
        │ miss
4. paid lookup API                metered, commercial terms
        │ miss
5. scraping fallback              last resort, tenant-scoped only, kill-switchable
        │ miss
6. ask the user                   photo, or type it
```

GS1 Verified by GS1 sits outside this cascade. It may be queried live to validate that a barcode is structurally real and to identify the brand owner, but **nothing from GS1 is ever stored**. Its terms prohibit permanent copies and prohibit making the content available as part of another product or service, and the value-added carve-out explicitly excludes replication. Quoted in `legal-and-privacy.md`.

### The MVP bug worth naming

`searchInTeamDatabase()` succeeded into a bare `// TODO: Open the product page if found` and only advanced to the next stage inside its `catch` block. So finding a product in your own inventory hung the screen forever, and the cascade only worked when the product was not found. The most common case was the broken one.

Here, a hit at any stage produces an immediate, visible result.

## What each stage returns

Every stage produces the same structure, so the UI is built once: name, brand, description, category, image, unit hint, source, and a confidence score.

Confidence matters at presentation. A hit from the tenant's own products is authoritative. A scraped hit is shown as unverified and the user is invited to correct it, which is both honest and how the catalog improves.

## The community catalog

The moat, and the part that compounds.

When a user confirms a product that came from a lookup, a photo, or their own typing, they can contribute the text fields (not their photos) to the shared catalog. Opt-in per tenant, off by default.

Why it matters: Turkish product barcode coverage in commercial databases is weak. Every Turkish user who confirms a product makes the next Turkish user's scan work. No global competitor will assemble this, because they have no reason to care about Turkish grocery barcodes.

Contribution rules: the contributing team is recorded privately for audit, contributed rows carry `source = community`, photos are never contributed, and the terms grant a redistribution licence on the contributed fields only. Open questions in O5.

## The shared taxonomy

`product_categories` is seeded from the Google Product Taxonomy (free, published with a Turkish file), supplemented with Open Food Facts categories for grocery granularity. GS1 GPC was rejected because full access requires paid membership.

This exists because location suggestion needs a category vocabulary shared across tenants. The MVP had per-tenant free-text product types, so two tenants' categories shared nothing and cold-start signal was zero.

Tenants may still create their own categories. Those carry a `team_id` and do not participate in cross-tenant signal.

## Error and empty states

- **Total miss.** Offer photo recognition, then manual entry. Never a dead end. The MVP surfaced an exhausted quota here as a 403 with the message "your team has no limit for scanning barcodes" and no way forward.
- **Barcode with no product, twice.** If the same unknown barcode is scanned again, offer to reuse what the user entered last time.
- **Wrong match.** One tap to reject and re-resolve. A rejection is recorded, so the same wrong answer is not offered again to that tenant.
- **Damaged or unreadable barcode.** Manual entry of the digits, with checksum validation to catch typos.
- **Offline.** Stages 1 to 3 are local or cached and still work. Stages 4 and 5 queue and resolve later.
- **No AI credits.** Stages 1 to 3 are unaffected because they cost nothing. Only external lookup stops.

## Quota effects

- Stages 1 through 3 are free and always available.
- Stage 4 consumes credits, one per unique barcode lookup. A repeat scan of the same barcode is cached and free.
- Stage 5 consumes credits and is rate-limited independently.

## Acceptance criteria

1. Scanning a product already in the tenant's inventory shows it immediately, and offers to add stock. This is the case the MVP broke.
2. Scanning a Turkish grocery product not in the tenant's inventory resolves from some stage or offers photo recognition, and never dead-ends.
3. Continuous scanning of 20 items produces 20 resolutions without closing the camera between them.
4. Nothing sourced from GS1 is ever persisted. Verified by test.
5. Open Food Facts rows live only in `off_products` and never merge into `global_products`. Verified by test.
6. Every scraping source can be disabled independently without a deploy.
7. A `source = scraped` row is presented to the user as unverified.

## Open

- Which paid lookup provider, and whether more than one is needed for Turkish coverage. Go-UPC was used in the MVP; EAN-Search is the alternative. Turkish coverage for both is unmeasured.
- Whether the community catalog needs moderation before a contribution becomes visible to other tenants, or whether confidence scoring plus a report path is enough.
- How to present provenance without cluttering the UI. A user should be able to tell an authoritative match from a guess, but should not have to read a source label on every row.
