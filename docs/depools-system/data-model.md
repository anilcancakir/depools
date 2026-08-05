# Data model

This document is the source of truth for the Depools.ai schema. It defines every table, the tenancy rule, and the two structures the whole product rests on: the append-only movement ledger and lot-level expiry tracking.

Read `features/inventory-core.md` for the behaviour built on top of this.

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
| `default_shelf_life_days` | integer, nullable | used to pre-fill an expiry date suggestion |
| `par_level` | decimal(12,3), nullable | user-set target quantity, used before there is enough history to forecast |
| `reorder_point` | decimal(12,3), nullable | computed or user-set, see features/forecasting.md |
| `created_at`, `updated_at`, `deleted_at` | timestamps | soft delete |

Unique: (`team_id`, `sku`) where `sku` is not null.

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
| `closed_at` | timestamp, nullable | set when `remaining_quantity` reaches zero |
| `created_at`, `updated_at` | timestamps | |

Indexed: (`team_id`, `expires_at`) for the expiry list, (`product_id`, `location_id`, `closed_at`) for FEFO selection.

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
| `reference_type`, `reference_id` | nullable morph | links to the receipt, invoice or shopping list that caused it |
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

### product_stock (materialised view or maintained table)

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
| `source` | enum | `community`, `open_food_facts`, `paid_lookup`, `scraped` |
| `source_ref` | string, nullable | provenance for audit and takedown |
| `image_phash` | string(32), nullable, indexed | perceptual image hash, image dedup only |
| `name_hash` | string(32), nullable, indexed | md5 of the normalised name, text cache only |
| `confidence` | smallint | 0 to 100, lower for scraped and AI-generated |
| `created_at`, `updated_at` | | |

The MVP wrote a perceptual image hash and an md5 of the product name into the *same* `hash` column, so nothing downstream could tell which kind of hash it was looking at. Here they are two columns with two meanings.

`source` is not decoration. It drives retention, whether a row may be shared with other tenants, and how a takedown is executed. See `legal-and-privacy.md`.

Open Food Facts derived rows are held in a **separate table** (`off_products`) rather than merged into `global_products`, because ODbL's share-alike obligation attaches to a combined database. Isolation keeps the obligation contained to rows that are already open data.

### barcodes and product_barcode

`barcodes` is global: `code`, `symbology`, unique on (`code`, `symbology`). `symbology` is not nullable, unlike the MVP where a null and a non-null type produced two rows for the same physical barcode.

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
