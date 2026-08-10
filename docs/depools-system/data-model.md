# Data model

This document is the source of truth for the Depools.ai schema. It defines every table, the tenancy rule, and the two structures the whole product rests on: the append-only movement ledger and lot-level expiry tracking.

Read `features/inventory-core.md` for the behaviour built on top of this.

> **The schema is now built, and building it corrected this document in nine places.** Each correction
> is inline below with its decision number, and each came from measurement or from a primary source
> rather than from a rereading. The ones worth knowing before you read anything else:
>
> | This document said | The built schema does | Why |
> |---|---|---|
> | `barcodes` unique on `(code, symbology)` | unique on a canonical 14-digit `gtin`, symbology demoted to metadata | GS1's own text: store a GTIN as 14 digits. The pair made one product read three ways into three rows (D85) |
> | `source` includes `open_food_facts` | it does not, and a CHECK refuses it | ODbL isolation means such a row lives in `off_products` and can never appear there, so the value was unreachable (D87) |
> | a movement references the receipt | it references the receipt LINE | D51's undo has to reverse one wrong line of twenty-two (D96) |
> | `product_stock` is "a materialised view or maintained table" | a table maintained by `StockWriter` | Anılcan's call over a trigger, which makes the consistency check mandatory rather than a safety net (D81) |
> | raw extraction lives on the receipt row | its own table, one row per attempt | fallback means several attempts, and that table is O2's bake-off evidence (D95) |
> | 7 invariants | 10, and the schema enforces more of them than a test could | D27 and D28 added three |
>
> Three tables are also new since this was written: `product_aliases` and `global_product_aliases`
> (D89, because the promise that confirmations strengthen the cascade had no mechanism) and
> `ai_credit_grants` (D106, because a credit balance has to be derived for the same reason a stock
> balance does).
>
> The full record is `open-decisions.md`, D72 to D111.

## The two decisions that shape everything

**1. Stock is a ledger, not a number.**

The previous MVP stored `product_locations.quantity` as a mutable decimal and updated it in place. There was no history table of any kind. That single choice made the entire product promise impossible: without a movement history you cannot compute consumption rate, cannot predict a stockout, cannot measure waste, cannot answer "who took the last one", and cannot audit anything.

So: every change to stock is an immutable row in `stock_movements`. Current quantity is derived from the ledger and materialised for read performance, never authored directly.

**2. Expiry belongs to a lot, not a product.**

Three cartons of milk on the same shelf have three different expiry dates. A single date column on the product or on the product-location pair cannot express that. So inbound stock creates a `stock_lot`, and movements reference the lot they affect. Consumption defaults to FEFO (first expired, first out).

A lot is created for every inbound movement, whether or not the user supplied an expiry date. A lot with `expires_at IS NULL` is the normal case for non-perishables and costs nothing extra.

## Tenancy

Every business table carries `team_id` and is filtered by a global scope resolved from the authenticated user's current team. Three rules, all non-negotiable:

1. `team_id` is resolved from the auth context only. It is never read from a request parameter, a tool argument, or an MCP call argument. This is the exact failure that leaked data across roughly 1,000 organisations in Asana's MCP incident in 2025, and it went unnoticed for over a month.
2. Cross-tenant reads return 404, not 403, so a tenant cannot enumerate another tenant's identifiers.
3. Every table with `team_id` gets a test that proves a second tenant cannot read or write the first tenant's rows. These tests are written before the feature, not after.

Tables without `team_id` are global and shared on purpose: `barcodes`, `global_products`, `product_categories`. See "The shared catalog" below for why that is safe.

## Core tables

### products

The catalog entry for a thing the tenant holds. Holds no quantity.

| Column | Type | Notes |
|---|---|---|
| `id` | uuid, pk | |
| `team_id` | uuid, fk teams, indexed | tenancy |
| `product_category_id` | uuid, fk product_categories, nullable | shared taxonomy, see below |
| `global_product_id` | uuid, fk global_products, nullable | provenance if resolved from the catalog |
| `name` | string(255) | |
| `brand` | string(255), nullable | |
| `description` | text, nullable | |
| `sku` | string(64), nullable, indexed | tenant-assigned |
| `image_path` | string, nullable | |
| `base_unit` | string(16) | the unit stock is stored in, e.g. `adet`, `kg`, `lt` |
| `tracks_expiry` | boolean, default false | when true, capture asks for an expiry date |
| `default_shelf_life_days` | integer, nullable | used to pre-fill an expiry date suggestion, and to derive the warning window (D24) |
| `opened_shelf_life_days` | integer, nullable | the after-opening limit (D27). Null means opening is not an event for this product |
| `content_amount` | decimal(12,3), nullable | what one `base_unit` contains (D25): 1000 for a 1 lt carton, 3 for a pack of three |
| `content_unit` | string(16), nullable | the content's unit, `ml` / `g` / `poşet`. Null together with `content_amount` |
| `tracking_mode` | enum `lot`, `serial`, default `lot` | how units are identified (D28). Never asked at creation (D30); flipped from the detail screen |
| `par_level` | decimal(12,3), nullable | user-set target quantity, used before there is enough history to forecast |
| `reorder_point` | decimal(12,3), nullable | computed or user-set, see features/forecasting.md |
| `created_at`, `updated_at`, `deleted_at` | timestamps | soft delete |

Unique: (`team_id`, `sku`) where `sku` is not null.

`content_amount` and `content_unit` are the ONE declaration D25 allows on the product itself, and they are what the partial-quantity display renders ("2 adet + 500 ml"). They do not replace `product_units`: that table holds purchase-side conversions (a `koli` of 12), while these describe what a single base unit is made of. Turkish labelling law states the same pair on the pack, per-unit net content plus pack count, so the fields mirror what the box already carries.

`tracking_mode` is effectively immutable in the `serial` direction: a product with serials cannot go back to lots, because the serials have no fungible quantity to collapse into. Enforced at validation, not by the column.

### product_units

Package-to-base conversions, so "2 koli su" resolves to a base quantity. Modelled as a relative conversion chain rather than a unit-category table, following the direction Odoo itself moved when its rigid category model could not express real packaging hierarchies.

| Column | Type | Notes |
|---|---|---|
| `id` | uuid, pk | |
| `product_id` | uuid, fk products, indexed | |
| `unit` | string(32) | e.g. `koli`, `paket`, `düzine` |
| `factor` | decimal(12,4) | how many `base_unit` one `unit` equals |
| `created_at`, `updated_at` | timestamps | |

Unique: (`product_id`, `unit`).

### locations

A user-named hierarchy. Depth is arbitrary but bounded.

| Column | Type | Notes |
|---|---|---|
| `id` | uuid, pk | |
| `team_id` | uuid, fk teams, indexed | |
| `parent_location_id` | uuid, fk locations, nullable, indexed | self-reference |
| `name` | string(255), indexed | user's own words, e.g. `Mutfak Dolabı`, `Çekmece 2` |
| `path` | string, indexed | materialised ancestor path, maintained on write |
| `depth` | smallint | enforced maximum of 6 |
| `icon_id` | uuid, fk icons, nullable | |
| `created_at`, `updated_at`, `deleted_at` | timestamps | |

The MVP walked `parent_location_id` recursively with no depth limit and no cycle guard. Here `path` and `depth` are maintained on write, a cycle is rejected at validation, and depth is capped.

### stock_lots

One row per inbound batch of a product at a location. The unit of expiry.

| Column | Type | Notes |
|---|---|---|
| `id` | uuid, pk | |
| `team_id` | uuid, fk teams, indexed | |
| `product_id` | uuid, fk products, indexed | |
| `location_id` | uuid, fk locations, indexed | |
| `lot_code` | string(64), nullable | supplier batch code if known |
| `expires_at` | date, nullable | null means non-perishable or unknown |
| `received_at` | timestamp | |
| `unit_cost` | decimal(12,4), nullable | for waste valuation |
| `currency` | string(3), nullable | |
| `initial_quantity` | decimal(12,3) | in the product's `base_unit` |
| `remaining_quantity` | decimal(12,3) | materialised from the ledger, never authored directly |
| `opened_at` | timestamp, nullable | when this lot was opened (D27). Null means sealed |
| `closed_at` | timestamp, nullable | set when `remaining_quantity` reaches zero |
| `created_at`, `updated_at` | timestamps | |

Indexed: (`team_id`, `expires_at`) for the expiry list, (`product_id`, `location_id`, `closed_at`) for FEFO selection.

**The binding date is not always `expires_at`.** Once `opened_at` is set, the lot must be used within `products.opened_shelf_life_days` of that moment, which is usually much sooner than the printed date: a carton with a week left on the box has three days left once opened. Every surface that asks "what expires first" resolves the earlier of the two, and FEFO prefers an open lot over a merely-earlier printed date. See D27 and `features/stock-movements.md`.

Opening is recorded as a movement so the ledger stays the only writer of state. It carries `reason = consumption` with a partial `delta` when the user consumed part of a sealed unit, which is what sets `opened_at` in the same transaction; the user never declares "I am opening this" (D30's sibling reasoning, and D13).

### product_serials

One row per physical unit, for a product whose `tracking_mode` is `serial` (D28).

| Column | Type | Notes |
|---|---|---|
| `id` | uuid, pk | |
| `team_id` | uuid, fk teams, indexed | tenancy |
| `product_id` | uuid, fk products, indexed | |
| `location_id` | uuid, fk locations, indexed, nullable | null once it has left |
| `serial` | string(128) | the serial, IMEI or asset tag as printed |
| `warranty_ends_at` | date, nullable | reuses the expiry machinery: same derived window, same badge, same attention list |
| `unit_cost` | decimal(12,4), nullable | |
| `currency` | string(3), nullable | |
| `acquired_at` | timestamp | |
| `released_at` | timestamp, nullable | when it left. The row is kept, not deleted |
| `created_at`, `updated_at` | timestamps | |

Unique: (`team_id`, `product_id`, `serial`).

A serial-tracked product holds no `stock_lots`: quantity is the count of rows with `released_at IS NULL`, so there is nothing to sum and no fraction to express. Half a drill does not exist, which is why the two modes are mutually exclusive by nature rather than by policy.

A movement against a serial-tracked product references the unit through `reference_type`/`reference_id` rather than `stock_lot_id`, and its `delta` is always plus or minus one.

### stock_movements

The ledger. Append-only. No updates, no deletes. A mistake is corrected by writing a compensating movement, which is why `reason` includes `correction`.

| Column | Type | Notes |
|---|---|---|
| `id` | uuid, pk | |
| `team_id` | uuid, fk teams, indexed | |
| `product_id` | uuid, fk products, indexed | denormalised for query speed |
| `location_id` | uuid, fk locations, indexed | |
| `stock_lot_id` | uuid, fk stock_lots, indexed | which lot this movement affects |
| `delta` | decimal(12,3) | positive inbound, negative outbound, in `base_unit` |
| `reason` | enum | see below |
| `source` | enum | see below |
| `actor_type` | enum | `user`, `assistant`, `mcp_client`, `system` |
| `actor_id` | uuid, nullable | the user, or null for system |
| `note` | text, nullable | free text, treated as untrusted input |
| `reference_type`, `reference_id` | nullable morph | links to the receipt LINE, invoice or shopping list that caused it. The line rather than the document (D96), so an undo can reverse one wrong line of twenty-two |
| `idempotency_key` | string(64), nullable, unique per team | protects against double submission |
| `occurred_at` | timestamp, indexed | when it happened in the real world |
| `created_at` | timestamp | when we recorded it |

`reason` values, and this list is load-bearing because forecasting and waste metrics are computed by filtering on it:

- `purchase`: bought and brought in.
- `consumption`: used or sold in the normal course of business.
- `waste`: thrown away, spoiled, broken. Never folded into `consumption`, because waste percentage and sell-through-before-expiry are exactly the ratio of this reason to total outflow.
- `stock_take`: a counted correction after a physical count.
- `correction`: fixing a data-entry error.
- `transfer_in`, `transfer_out`: a move between locations, always written as a pair.
- `return`: sent back to the supplier.

`source` values, recording which surface created the movement: `manual`, `receipt`, `invoice`, `barcode`, `photo`, `assistant`, `mcp`, `import`, `shopping_list`.

### product_stock (a table, maintained by `StockWriter`)

Derived current quantity per (product, location). Exists only so list screens and search do not aggregate the ledger on every read.

| Column | Type |
|---|---|
| `team_id`, `product_id`, `location_id` | composite key |
| `quantity` | decimal(12,3) |
| `earliest_expires_at` | date, nullable |
| `lots_count` | integer |
| `updated_at` | timestamp |

Rebuildable from `stock_movements` at any time. A scheduled consistency check compares it against the ledger and reports drift; the ledger always wins.

## The shared catalog

Three global tables let a barcode scanned by one tenant help the next. They hold no tenant data.

### global_products

| Column | Type | Notes |
|---|---|---|
| `id` | uuid, pk | |
| `name`, `brand`, `description` | | |
| `product_category_id` | uuid, nullable | shared taxonomy |
| `locale` | string(5), indexed | one row per locale |
| `image_path` | string, nullable | |
| `source` | enum | `community`, `paid_lookup`, `scraped`, `ai_generated`. **Not `open_food_facts`** (D87): ODbL isolation puts those rows in `off_products`, so the value could never be written and an unreachable value in a whitelist is an invitation |
| `source_ref` | string, nullable | provenance for audit and takedown |
| `image_phash` | string(32), nullable, indexed | perceptual image hash, image dedup only |
| `name_hash` | string(32), nullable, indexed | md5 of the normalised name, text cache only |
| `confidence` | smallint | 0 to 100, lower for scraped and AI-generated |
| `created_at`, `updated_at` | | |

The MVP wrote a perceptual image hash and an md5 of the product name into the *same* `hash` column, so nothing downstream could tell which kind of hash it was looking at. Here they are two columns with two meanings.

`source` is not decoration. It drives retention, whether a row may be shared with other tenants, and how a takedown is executed. See `legal-and-privacy.md`.

Open Food Facts derived rows are held in a **separate table** (`off_products`) rather than merged into `global_products`, because ODbL's share-alike obligation attaches to a combined database. Isolation keeps the obligation contained to rows that are already open data.

### barcodes and product_barcode

`barcodes` is global, and its identity was corrected while building it (D85). GS1's own recommendation is that a GTIN is always stored as 14 digits, zero-padded, and uniqueness on `(code, symbology)` broke that: one physical product read as UPC-A `012345678905`, as EAN-13 `0012345678905` and from a case label as ITF-14 `10012345678902` became three rows for one yoghurt. The MVP's nullable-symbology bug recorded here was the shallow version of the same problem.

So a GTIN row is keyed on `gtin CHAR(14)` alone and carries no symbology, because the same GTIN is legitimately read as UPC-A on the item and ITF-14 on the case. A non-GTIN row (a Code128 internal label, a QR, a DataMatrix) has no GTIN and is keyed on `(code, symbology)` instead. A CHECK enforces that exactly one regime applies, and each gets its own partial unique index.

`product_barcode` links a tenant's product to a barcode. `global_product_barcode` links a catalog entry to a barcode.

### product_categories

The shared taxonomy that makes location suggestion work. Seeded from the Google Product Taxonomy, which is free and published with a Turkish file, supplemented with Open Food Facts categories for grocery granularity. GS1 GPC was rejected: full access needs paid membership.

This replaces the MVP's per-tenant free-text `product_types`, which gave no cold-start signal at all because two tenants' categories shared no vocabulary.

Tenants may still create their own categories; those rows carry a `team_id` and do not participate in cross-tenant signal.

### location_category_affinity

The counting table behind automatic location suggestion. Per tenant, not shared.

| Column | Type |
|---|---|
| `team_id`, `product_category_id`, `location_id` | composite key |
| `count` | integer |
| `updated_at` | timestamp |

Incremented when a placement is accepted, decremented and re-pointed when the user overrides. This is the whole model. There is no training pipeline, the next suggestion reflects the last correction immediately, and the count itself is the explanation shown to the user. See `features/location-assignment.md`.

## Capture and monetization tables

- `receipts`: one row per captured receipt or invoice. Holds the image or XML path, `kind` (`fis`, `e_arsiv`, `e_fatura`, `order_email`), extraction status, raw extracted payload, and the movements it produced.
- `receipt_lines`: extracted line items with a confidence score and a resolution state (`unresolved`, `matched`, `created`, `rejected`), so a partially confirmed receipt can be resumed.
- `shopping_lists` and `shopping_list_items`: generated or manual, with the reason each item was suggested.
- `plans`, `plan_prices`, `subscriptions`, `payments`: see `monetization.md`. Metering is on unique SKU count, AI credits and history retention window, not the MVP's five simultaneous axes.
- `ai_usage_events`: one row per billable AI action with token counts and computed cost, so a credit balance is auditable. The MVP stored token counts and never aggregated them.

Identity, teams, memberships, invitations, sessions and notifications are **not defined here**. They come from `magic-starter-laravel` and are configured, not written. See `architecture.md`.

## Invariants

Statements that must hold, each of which deserves a test:

1. For every (product, location): `product_stock.quantity` equals the sum of `stock_movements.delta`.
2. For every lot: `remaining_quantity` equals `initial_quantity` plus the sum of its movement deltas, and is never negative.
3. Every outbound movement references a lot belonging to the same product, location and team.
4. `stock_movements` rows are never updated or deleted. Enforced at the model level and asserted in tests.
5. A transfer writes exactly two movements with equal and opposite deltas and a shared reference.
6. No query returns a row whose `team_id` differs from the authenticated team.
7. `locations.depth` never exceeds 6, and no location is its own ancestor.
8. A product has `stock_lots` or `product_serials`, never both. `tracking_mode` decides which, and a product with serials never returns to `lot`.
9. For a serial-tracked product, quantity equals the count of `product_serials` rows with `released_at IS NULL`, and every movement's `delta` is plus or minus one.
10. A lot with `opened_at` set resolves its binding date as the earlier of `expires_at` and `opened_at + products.opened_shelf_life_days`.

### What the database enforces, and what still needs a test

Building the schema moved several of these from "deserves a test" to "cannot happen", which is worth
distinguishing because the two need different work.

**In the database**, as a CHECK or a partial unique index: invariant 7's depth cap; invariant 3 and 4's
referential half (`restrictOnDelete` on the ledger's product, location and lot, so a force delete cannot
take history with it); `(team_id, sku)` uniqueness, which this document asked for and which held nowhere
until PostgreSQL arrived; a barcode's two identity regimes; a receipt's two deduplication regimes; a
resolved receipt line pointing somewhere; a serial's label printing once; only the first attempt of an AI
action carrying a charge; and one plan allowance per period.

**In the application**, because a CHECK cannot see another table and D84 rules out the trigger that
could. Each of these now has a named mechanism rather than an intention:

| Rule | What holds it |
|---|---|
| invariant 1, projection equals the ledger | `StockConsistency`'s three projection checks, run nightly by `depools:check-consistency` (D81's second obligation, D110) |
| invariant 2, a lot's total | the same sweep, including `lot_overdrawn`, which compares against the UNCLAMPED sum because `recalculateFromLedger` stores `max($sum, 0)` and a lot the ledger drove negative otherwise sits at zero looking correct |
| invariant 4, append-only | the model throws on update and delete; `restrictOnDelete` is the referential half |
| invariant 5, a transfer's paired rows | `StockWriterTest::test_invariant_5_a_transfer_is_two_equal_and_opposite_movements` |
| invariant 8, lots XOR serials | three mechanisms, one per failure mode: a vocabulary CHECK, a model transition guard, and `StockWriter::receive` refusing a serial-tracked product (D109) |
| invariant 9, a serial's quantity and unit deltas | `serial_quantity_drift` and `serial_unit_delta` in the sweep |
| D88, the normalisation fold | `name_normalized_drift` in the sweep, plus `NameNormalizationTest` pinning the fold itself |
| D81's FIRST obligation, that only `StockWriter` writes | `LedgerWritersTest`, which pins the set of files that can REACH each derived table |

Six of the nine sweep checks are repairable, because their invariant names an authority: the ledger. The
other three are questions about a shelf rather than about arithmetic, so `repair()` refuses them out
loud. The scheduled run never repairs anything at all (D110): drift is the evidence that a writer
bypassed the service, and a nightly repair would tidy that evidence away every night.

Invariants 8 and 9 were untestable when this was written because `product_serials` did not exist. It does
now, and so does `ProductSerial`.
