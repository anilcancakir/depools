# Feature: inventory core

> Summary depth. Deepens after the design mockups settle the interaction decisions.

Products, locations, lots and the movement ledger. Everything else in the product writes into this or reads out of it.

Schema in `data-model.md`. Decisions D3 and D8 in `open-decisions.md`.

## What the user does

- Creates a product: a name, optionally a brand, SKU, photo, category, base unit, and whether it expires.
- Builds a location hierarchy in their own words: "Depo" > "Raf 3" > "Kutu B".
- Records stock coming in, with a quantity, a location, and an expiry date when the product tracks expiry.
- Records stock going out, choosing a reason: used, sold, wasted, transferred, counted.
- Sees, for any product, how much exists in each location and which lot expires first.
- Sees, for any location, everything in it including nested locations.
- Sees what expires soon, across everything.

## The ledger

Every change is an append-only row. Nothing is edited in place, nothing is deleted.

A mistake is fixed by writing a compensating movement with reason `correction`, which keeps the record truthful about both what happened and when it was corrected. This is what makes the audit trail worth having.

Balances are derived and materialised into `product_stock` for read speed, with a scheduled consistency check. When the check finds drift, the ledger wins and the projection is rebuilt.

## Lots and FEFO

Inbound stock always creates a lot. A lot with `expires_at IS NULL` is the ordinary case for non-perishables and costs nothing.

Outbound stock consumes from the lot that expires first (FEFO), unless the user picks a specific lot. The user can always override, because reality sometimes disagrees with the algorithm.

When a lot reaches zero it is closed rather than deleted, so history stays queryable within the tenant's retention window.

## Units

A product has one base unit, stored on the product. Package units are conversions to it: `1 koli = 12 adet`.

Capture accepts whatever unit the user says. "2 koli su" resolves through `product_units` to 24 base units. If the unit is unknown, the user is offered a one-time definition rather than being blocked:

```
"koli" birimini tanımla:
1 koli = [12] adet   [Kaydet]
```

Stock is always stored in the base unit. Display may use whichever unit the user last used for that product.

## Error and empty states

- **No products yet.** The empty state offers the three fastest capture paths (scan, receipt photo, say it), not a "Create product" button.
- **No locations yet.** First capture creates a default location rather than blocking. The user renames it later.
- **Negative stock.** Rejected at validation with the current balance shown. An outbound movement larger than what exists is almost always a data-entry error, and permitting it corrupts every downstream number.
- **Lot ambiguity.** When several lots could satisfy an outbound movement, FEFO decides and the chosen lot is shown, not hidden.
- **Location cycle.** Rejected at validation. Depth beyond 6 is rejected with an explanation.
- **Double submission.** The idempotency key on commit makes a retry a no-op rather than double-counting.

## Quota effects

- Creating a product counts against the unique SKU meter. At the limit, everything existing keeps working and only new product creation is blocked, with an in-context upgrade prompt.
- Movements are never metered. A user must always be able to record what they just did.
- History beyond the retention window becomes unqueryable, never deleted.

## Acceptance criteria

1. A new tenant records their first product and its stock in under 60 seconds, from an empty state, without documentation.
2. For every (product, location), the materialised balance equals the sum of ledger deltas. Verified by test and by the scheduled consistency check.
3. Three inbound movements of the same product with different expiry dates produce three lots, and the next outbound consumes the earliest.
4. A correction leaves both the original movement and the correction visible in history.
5. A transfer between locations produces exactly two movements with equal and opposite deltas and a shared reference.
6. A second tenant cannot read or write any row belonging to the first. Tested per table.
7. `remaining_quantity` never goes negative under any sequence of operations, including concurrent ones.

## Open

- Whether stock take (guided physical count) lands in v1 or v2. Currently v2, but if early users ask for it during design it is cheap because the ledger already models the correction.
- Whether a product can have per-location par levels rather than one global par level. Depends on whether early users actually manage the same product differently per location.
