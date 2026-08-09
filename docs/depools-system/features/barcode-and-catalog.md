# Feature: barcode scanning and the product catalog

> Summary depth. Deepens after the design mockups settle the interaction decisions.

Scan a barcode, get a product. Build a Turkish product catalog nobody else has, without breaking anyone's licence.

Decision D11 in `open-decisions.md`. Licence positions in `legal-and-privacy.md`.

## Scanning

`mobile_scanner` on all three platforms. It supports web through three selectable backends, unlike the ML Kit package which is Android and iOS only, and it carries roughly nine times the adoption.

Symbologies: EAN-13, EAN-8, UPC-A, UPC-E, Code128, Code39, QR, DataMatrix.

The MVP's scanner never worked. The camera widget was commented out in `barcode_scanner.dart` and only manual entry functioned. Continuous scanning matters here: unpacking a delivery means scanning twenty things in a row, so the scanner stays open and accumulates rather than closing after each hit.

### What the web target does not get, and what that costs the design

Verified against `mobile_scanner` 7.4.0 (pub.dev, August 2026). It covers Android (CameraX + ML Kit), iOS and macOS (AVFoundation + Apple Vision) and web (a selectable ZXing or `BarcodeDetector` backend). Three of its features are Android/iOS/macOS only, and two of those three are load-bearing here:

**`scanWindow` is unsupported on web, so the viewfinder rectangle is an aiming aid and not a gate.** On a phone that rectangle genuinely restricts detection to the region inside it. On web there is no region restriction: the whole camera frame is decoded, and a barcode sitting outside the rectangle still registers. This does not justify a different UI per platform, which the layout rule forbids anyway. It justifies not writing copy that promises otherwise: the frame says where to aim, never "only this area counts". If a shelf holds two barcodes at once, web can pick the wrong one, so the confirmation step in the queue is what protects the user, not the frame.

**`analyzeImage` is unsupported on web, so reading a barcode out of a still photo cannot run on the device there.** That decides the architecture for photo capture rather than merely constraining it: the shelf photo and the receipt photo go to the backend, and the backend is what recognises them. This is the direction `ai-enrichment.md` and `receipt-ingestion.md` already take for the product recognition itself, so the two paths converge instead of splitting, and there is no on-device fallback worth building for one platform.

**Web autofocus is genuinely unreliable**, and it is device and browser dependent rather than something configuration fixes (`mobile_scanner` issue #835, open across several releases). The practical reading: on a desktop with a webcam, scanning is a worse experience than typing, so manual barcode entry stays a first-class control on the scan screen rather than a fallback hidden behind a failure.

Two smaller decisions the web backend forces:

- The recommended backend is the browser's native `BarcodeDetector` with a `zxing-wasm` fallback. Native is absent in Firefox and needs Safari 17+, so in practice a meaningful share of users land on the WASM path.
- That fallback pulls roughly 2 MB of WebAssembly from the jsDelivr CDN on first use. For a Turkey-first product that is a first-scan stall on a slow connection and a third-party dependency in the critical path. Self-hosting the binary alongside the app is the answer; it is not the default, so it has to be set up deliberately.

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

## The scan surface

**The camera never closes, so the result cannot be a screen.** Criterion 3 asks for twenty
items resolved without closing the camera between them, and that single line disqualifies
the obvious design: a modal per scan. Unpacking a delivery means scanning with both hands
busy, and a dialog dismissed twenty times is a dialog nobody reads.

So a scan lands in a QUEUE beside a live viewfinder, and confirmation happens once for the
whole batch. Each row shows the barcode (always, in mono, because resolution is a claim
about a machine reading and the label in the user's hand is the only check), what it
resolved to, how many times it was scanned, and provenance when there is any doubt.

**A repeat scan increments its row rather than appending one.** Six identical yoghurts are
one row reading six, not six rows and six commits. This has a consequence that is not
optional: the queue is ordered by LAST SCAN, most recent first. Ordered by first-seen, the
sixth scan would increment a row that had already scrolled away and the user would get no
feedback for a scan that worked.

The unmatched rows are therefore not floated to the top, which is the opposite of what the
receipt review screen does. The two screens differ for a reason: the paper is static and
triage is the task there, while here the camera is live and feedback beats triage. A count
above the commit button is what keeps the unmatched ones from disappearing upward.

**One destination for the batch.** A mixed delivery does go to different shelves, so this
looks like an oversimplification and is not: receiving and putting away are two events.
Everything lands where it was received; moving it onward is the transfer flow (D38). The
default is the last location used for receiving, NOT category affinity, because affinity
answers "where does this category go" and a batch of milk and screwdrivers cannot ask it.

**Both input paths exist everywhere; width decides which leads.** At phone width the
viewfinder leads, because the phone is the scanner and it is already pointed at a label. At
desktop width the digit field leads, because a desktop barcode reader is an HID keyboard
that types digits and a laptop webcam points at the operator's face. Same widgets, one
order token.

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
