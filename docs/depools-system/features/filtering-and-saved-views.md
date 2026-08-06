# Filtering and saved views

The stock list is the screen this product is used from, and filtering is how a user with more than about thirty products finds anything in it. So this is a feature document, not a UI note.

## What can be filtered

The axes are not a free choice. `ai-design.md` already fixed them, because `search_products` exposes free text, brand, SKU, barcode, tag, category and location to the assistant. **A filter the UI cannot express but the assistant can is a split product**: the user asks the assistant "kilerdeki bitmek üzere olanlar" and gets an answer, then cannot reproduce it by hand. So the UI covers the same axes, plus the two the list already groups by:

| Axis | Type | Source |
|---|---|---|
| free text | string, matches name, brand, SKU, barcode | `products.name`, `.brand`, `.sku`, `barcodes.code` |
| location | multi-select over a hierarchy | `locations`, nested; selecting a parent includes its descendants |
| category | multi-select | `product_categories`, shared taxonomy |
| tag | multi-select | product tags |
| brand | multi-select | `products.brand`, distinct values |
| stock state | one of: all, out of stock, below par, in stock | derived from the ledger against `par_level` |
| expiry | one of: any, expired, expiring soon | earliest lot expiry; the "soon" window is derived per product, see D24 |

Selecting a parent location includes everything under it. "Kiler" has to mean Kiler and its shelves, because a user who put a product on "Kiler › Raf 2" thinks of it as being in the pantry.

## Three surfaces, one job each

The research behind this is in the decision log below. The shape:

**1. The search field, inline above the list.** Free text and the exact-match lookups (barcode, SKU). HIG puts an inline search field directly above the content it searches when the search is scoped to that content rather than global, which is this case.

**2. A chip row directly under the search field**, with two modes that never mix:

- **Nothing applied** → the saved filters, as tappable chips. Quick access, no menu to open.
- **Something applied** → the active criteria, each as a chip with a × that removes just that one, plus "Temizle" and "Kaydet".

Mixing them is a documented failure: a row that holds saved filters, recent searches and active criteria under one visual treatment leaves the user unable to tell what is currently narrowing the list from what is merely available.

**3. The filter sheet**, behind the filter button. Every axis, grouped and collapsible, applied in a batch by a "N ürün göster" button rather than live as each checkbox flips.

## Why not filter tokens in the search field

Tokens (an iOS search field where "Kiler" becomes a pill inside the field) look like the Apple-native answer and are not, at this axis count. HIG's own guidance on tokens carries the caveat that "people may not know which tokens are available", and its illustration of search in a bottom toolbar shows a **separate Filter button beside the search field**, which is the layout this screen uses. Tokens are right for one or two well-known single-value refinements; nine axes including a hierarchical location tree is what a filter control is for.

Source: [HIG, Search fields](https://developer.apple.com/design/human-interface-guidelines/search-fields), Scope bars and tokens.

## Saved filters

**Explicit save, and saving is what pins it.** Linear, Todoist and Jira all separate "save this filter" from "put it somewhere I can reach it", because their saved lists grow long enough to need curation. This product does not have that problem yet: a household or a cafe will have a handful. So save puts the chip in the row, and there is no second pinning step to explain. Revisit this if a tenant ever has more saved filters than fit one scrollable row.

**A saved filter stores criteria, never results.** The known bug in this pattern is saving a filter that freezes today's matching rows, so tomorrow's newly expiring product never appears in "Yakında bitecek" and the user quietly stops trusting it. Saved filters are live queries by construction here: the stored shape is the criteria set, evaluated on every open.

**Three built-ins ship with the app**, because a filter the user has to build before they get any value from filtering is a filter they never build:

| Chip | Criteria |
|---|---|
| Süresi geçenler | expiry = expired |
| Yakında bitecek | expiry = inside the product's own window |
| Stok yok | stock state = out of stock |

These overlap the "Dikkat gerekiyor" section on purpose. The section is the always-visible summary of the same three conditions; the chip is the drill-in that shows only that one, unmixed and complete rather than truncated. Removing either would be worse: the section is what a user who never taps a filter still sees, and the chip is what they reach for when the section is not enough.

## The failure this is designed against

Filtering on mobile is measurably worse than on desktop: reported usage sits around a tenth of the desktop rate, and roughly half the users who open a mobile filter menu abandon it without applying anything. The documented cause is not the axis count, it is invisibility: applied filters that are not shown in the results view leave the user reading a shortened list, concluding the product is not there, and leaving.

That is why mode 2 of the chip row is not decoration. **The active criteria are always on screen while they are in force.** Every screenshot review of this screen should check that first: if a filter is applied and the row does not say so, the screen is broken regardless of how it looks.

## Settled since

**Saved filters are team-wide** (D22): `saved_filters(team_id, created_by)`, no share toggle and no per-user scope. A cafe's "Yarın bitecekler" is useful to every shift, and a per-user scope would mean each new employee starts from nothing.

**"Yakında bitecek" carries no day count** (D24). The window is the last fifth of the product's shelf life, so the chip cannot name a number without making a promise the filter does not keep.

## Open

- **Filter on the assistant's side.** The assistant can already express these as tool arguments. Whether a chat answer offers "bunu filtre olarak kaydet" is a v2 question, listed in `iterations.md`.
- **Whether the axes need a tracking-mode filter.** D28 puts lot-tracked and serial-tracked products in one catalogue. A user hunting a specific IMEI searches rather than filters, so this is probably not an axis, but it is unverified against a real serial-tracking workflow.
