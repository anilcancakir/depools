---
generated: from `lib/ui/components/` (see "How this file is kept true")
source: this app's own component library
last_updated: 2026-08-10
---

# Component Registry

Every component this app owns, so that a screen reaches for one that exists instead of scaffolding
a second one. `CLAUDE.md` requires reading this before writing any widget, which only works if it
describes what is actually on disk.

## What this file used to say, and why that mattered

Until this revision it listed 27 components at paths like `lib/ui/components/button/`,
`lib/ui/components/card/`, `lib/ui/components/input/`. **None of those directories exist.** Those
are `magic_starter`'s components, and they are imported as `MSButton`, `MSCard`, `MSInput` from the
package. At the same time 12 components this app really owns (`ProductRow`, `LotRow`, `StatCard`,
`ExpiryBadge`, `Quantity`, `SectionHeader`, and others) appeared nowhere.

So the file failed in exactly the way that costs the most: an agent following the rule found a
plausible entry for the thing it needed, at a path it could not import, and had no way to discover
the twelve real components it might have reused. Both halves of that produce duplicates.

## Look in `magic_starter` first

The generic layer lives in the package, not here: `MSButton`, `MSInput`, `MSSelect`, `MSCheckbox`,
`MSSwitch`, `MSCard`, `MSBadge`, `MSTabs`, `MSSegmentedControl`, `MSBottomSheet`, `MSEmptyState`,
`MSPageScaffold`, `MSPageHeader`, `MSPageContainer` and the rest of its 37. A component belongs in
this app only when it encodes something about depools that a generic library could not: a lot with
an expiry, a count line with a variance, a location with a depth.

## The components this app owns

| Folder | Class | Variant enums | Recipe | Preview | What it is |
|---|---|---|---|---|---|
| `callout/` | `Callout` | CalloutIntent | yes | yes | Callout |
| `chat_message/` | `ChatMessage` | ChatSpeaker | yes | yes | ChatMessage |
| `choice_chip/` | `ChoiceChip` | - | yes | yes | ChoiceChip |
| `count_row/` | `CountRow` | CountState | yes | yes | CountRow |
| `draft_field/` | `DraftField` | DraftFieldLayout, DraftFieldState | yes | yes | DraftField |
| `expiry_badge/` | `ExpiryBadge` | ExpiryUrgency | yes | yes | ExpiryBadge |
| `filter_bar/` | `FilterBar` | - | yes | yes | FilterBar |
| `filter_chip/` | `FilterChip` | - | yes | yes | FilterChip |
| `label_card/` | `LabelCard` | LabelCardSize | yes | yes | LabelCard |
| `label_item_row/` | `LabelItemRow` | LabelCountMode | yes | yes | LabelItemRow |
| `label_preview/` | `LabelPreview` | - | yes | yes | LabelPreview |
| `list_footer/` | `ListFooter` | ListFooterState | yes | yes | ListFooter |
| `location_row/` | `LocationRow` | - | yes | yes | LocationRow |
| `location_stock_row/` | `LocationStockRow` | - | yes | yes | LocationStockRow |
| `lot_row/` | `LotRow` | - | yes | yes | LotRow |
| `movement_row/` | `MovementRow` | MovementDirection | yes | yes | MovementRow |
| `option_row/` | `OptionRow` | - | yes | yes | OptionRow |
| `product_row/` | `ProductRow` | - | yes | yes | ProductRow |
| `quantity/` | `Quantity` | QuantitySize, QuantityTone | yes | yes | Quantity |
| `quantity_stepper/` | `QuantityStepper` | - | yes | yes | QuantityStepper |
| `receipt_line_row/` | `ReceiptLineRow` | LineResolution | yes | yes | ReceiptLineRow |
| `scan_row/` | `ScanRow` | ScanSource | yes | yes | ScanRow |
| `section_card/` | `SectionCard` | - | yes | yes | SectionCard |
| `section_header/` | `SectionHeader` | - | yes | yes | SectionHeader |
| `serial_row/` | `SerialRow` | - | yes | yes | SerialRow |
| `setup_step/` | `SetupStep` | - | yes | yes | SetupStep |
| `shelf_candidate_row/` | `ShelfCandidateRow` | - | yes | yes | ShelfCandidateRow |
| `shopping_row/` | `ShoppingRow` | ShoppingReason | yes | yes | ShoppingRow |
| `stat_card/` | `StatCard` | - | yes | yes | StatCard |
| `stock_badge/` | `StockBadge` | - | yes | yes | StockBadge |
| `tag/` | `Tag` | TagIntent, TagSize | yes | yes | Tag |

31 components.

## Layout infrastructure (not in the component library)

These live in `lib/ui/layouts/` because they are page structure rather than visual components, and
they have no preview: the catalog renders screens without a shell, which is the one place they do
not apply. `AssistantLauncher` moved here from the component library for that reason, rather than
growing a preview of a button that only exists inside a shell.

| File | Class | What it is |
|---|---|---|
| `page_chrome.dart` | `PageChrome`, `PageChromeHost` | Carries a page's pinned footer out of the shell's scroll, where it can be anchored to the viewport. |
| `app_page_scaffold.dart` | `AppPageScaffold` | `MSPageScaffold` plus a `footer:` that does not scroll away. |
| `assistant_launcher.dart` | `AssistantLauncher` | The floating assistant button and the full-screen overlay it opens. |

## How this file is kept true

There is no `design:registry` command. Until there is, regenerate the table above from disk rather
than editing rows by hand, which is how it drifted by 27 phantom entries in the first place:

```sh
# The table is derived from each component's class declaration and the first prose line of its
# doc block, so writing a real doc comment is what keeps the description useful.
ls -d lib/ui/components/*/
```

A `NO` in the Preview column is a rule violation, not a note: `.claude/rules/design.md` requires one
preview per component.
