---
generated: manual (design:registry planned)
source: magic_starter generic component library
last_updated: 2026-06-25
---

# Component Registry

Machine-readable manifest of every component in the app's `lib/ui/components/` library. Maps each component to its variants, token bindings, and anti-patterns.

> **design:registry note**: this file is intended to be generated and kept in sync by `make:component` and `previews:refresh`. Until that command emits it automatically, maintain it by hand when adding or modifying components.

---

## Primitives

Components backed by a Wind W-widget with no recipe layer.

---

## Form Inputs

### Button

- **File**: `lib/ui/components/button/`
- **Class**: `Button`
- **Recipe**: `WindRecipe` in `button.recipe.dart`
- **Variants**:
  - `intent`: `primary` | `secondary` | `ghost` | `destructive`
  - `size`: `sm` | `md` | `lg`
- **Default variants**: `intent=primary`, `size=md`
- **Token bindings**:
  - `primary`: `bg-primary text-on-primary`
  - `secondary`: `bg-surface-container text-fg border border-color-border`
  - `ghost`: `bg-transparent text-fg-muted`
  - `destructive`: `bg-destructive text-on-destructive`
  - `sm`: `text-xs px-3 py-1.5`
  - `md`: `text-sm px-4 py-2`
  - `lg`: `text-base px-6 py-3`
- **Anti-patterns**:
  - Do not use more than one primary button per section.
  - Do not use destructive intent outside confirm dialogs without a secondary confirmation step.
  - Do not hardcode colors via `className` override when a variant covers the case.

---

### Input

- **File**: `lib/ui/components/input/`
- **Class**: `Input`
- **Recipe**: `WindRecipe` in `input.recipe.dart`
- **Variants**:
  - `state`: `default` | `error`
- **Default variants**: `state=default`
- **Token bindings**:
  - `default`: `bg-surface-container-high border border-color-border text-fg`
  - `error`: `bg-surface-container-high border border-color-destructive text-fg`
- **Anti-patterns**:
  - Do not render error state without an error message in the parent `FormField`.
  - Do not use raw `WInput` directly; prefer `Input` so the recipe layer is consistent.

---

### Textarea

- **File**: `lib/ui/components/textarea/`
- **Class**: `Textarea`
- **Recipe**: `WindRecipe` in `textarea.recipe.dart`
- **Variants**:
  - `state`: `default` | `error`
- **Default variants**: `state=default`
- **Token bindings**: same as Input.
- **Anti-patterns**: same as Input.

---

### Checkbox

- **File**: `lib/ui/components/checkbox/`
- **Class**: `Checkbox`
- **Recipe**: `WindRecipe` in `checkbox.recipe.dart`
- **Variants**: none (state is driven by `checked:` prefix)
- **Token bindings**:
  - unchecked: `border-color-border bg-surface-container-high`
  - checked (`checked:` state): `bg-primary border-primary`
- **Anti-patterns**:
  - Do not use Material `Checkbox`; always use this component.

---

### Switch

- **File**: `lib/ui/components/switch/`
- **Class**: `Switch`
- **Recipe**: `WindRecipe` in `switch.recipe.dart`
- **Variants**: none (state is driven by `checked:` prefix on track/thumb)
- **Token bindings**:
  - track off: `bg-surface-container border-color-border`
  - track on (`checked:`): `bg-primary`
  - thumb: `bg-surface`
- **Anti-patterns**:
  - Do not use Material `Switch`.
  - Do not animate thumb translate outside the Wind checked state prefix.

---

### Radio

- **File**: `lib/ui/components/radio/`
- **Class**: `Radio`
- **Generic type**: `Radio<T>`
- **Recipe**: `WindRecipe` in `radio.recipe.dart`
- **Variants**: none (state is driven by `selected:` prefix)
- **Token bindings**:
  - unselected: `border-color-border bg-surface-container-high`
  - selected (`selected:`): `bg-primary border-primary`
- **Anti-patterns**:
  - Do not use Material `Radio`.
  - Group state management is the caller's responsibility (pass `groupValue`).

---

## Display

### Badge

- **File**: `lib/ui/components/badge/`
- **Class**: `Badge`
- **Recipe**: `WindRecipe` in `badge.recipe.dart`
- **Variants**:
  - `tone`: `neutral` | `primary` | `accent` | `success` | `warning` | `destructive` | `outline`
- **Default variants**: `tone=neutral`
- **Token bindings**:
  - `neutral`: `bg-surface-container text-fg-muted`
  - `primary`: `bg-primary-container text-primary`
  - `accent`: `bg-accent text-on-primary`
  - `success`: `bg-success text-on-primary`
  - `warning`: `bg-warning text-on-primary`
  - `destructive`: `bg-destructive-container text-destructive`
  - `outline`: `bg-transparent text-fg border border-color-border`
- **Anti-patterns**:
  - Do not use badges for interactive elements; they are display-only.
  - Do not use raw hex to create a custom tone; add a new variant value instead.

---

### Typography

- **File**: `lib/ui/components/typography/`
- **Class**: `Typography`
- **Recipe**: `WindRecipe` in `typography.recipe.dart`
- **Variants**:
  - `variant`: `h1` | `h2` | `h3` | `body` | `caption`
- **Default variants**: `variant=body`
- **Token bindings**:
  - `h1`: `text-3xl font-bold text-fg leading-tight tracking-tight`
  - `h2`: `text-2xl font-bold text-fg`
  - `h3`: `text-xl font-semibold text-fg`
  - `body`: `text-sm text-fg`
  - `caption`: `text-xs text-fg-muted`
- **Anti-patterns**:
  - Do not use raw `WText` for typographic content; use `Typography` so the scale is consistent.
  - Semantics (h1/h2) are secondary to hierarchy; a section title can use `h2` even inside a card.

---

### Skeleton

- **File**: `lib/ui/components/skeleton/`
- **Class**: `Skeleton`
- **Recipe**: `WindRecipe` in `skeleton.recipe.dart`
- **Variants**:
  - `shape`: `block` | `text` | `circle`
- **Default variants**: `shape=block`
- **Token bindings**:
  - all shapes: `bg-surface-container-high motion-safe:animate-pulse`
- **Anti-patterns**:
  - Use `Skeleton` instead of spinners for content loading states.
  - Do not animate outside `motion-safe:` prefix (respect `disableAnimations`).

---

## Card

### Card (migrated from MagicStarterCard)

- **File**: `lib/ui/components/card/`
- **Class**: `Card`
- **Enum**: `CardVariant`
- **Recipe**: `WindRecipe` in `card.recipe.dart`
- **Variants**:
  - `tone`: `surface` | `inset` | `elevated`
- **Default variants**: `tone=surface`
- **Token bindings**:
  - `surface`: `bg-surface-container border border-color-border`
  - `inset`: `bg-surface-container-high`
  - `elevated`: `bg-surface shadow-sm`
- **Slots**: `header`, `child` (body), `footer`
- **Anti-patterns**:
  - Do not bake CardVariant logic into child components; pass `tone` to `Card` at the call site.
  - Do not use `elevated` on dark backgrounds where shadow is invisible; prefer `surface` with a border.

---

## Selection

### Select

- **File**: `lib/ui/components/select/`
- **Class**: `Select`
- **Recipe**: `WindSlotRecipe` in `select.recipe.dart`
- **Slots**: `trigger`, `popup`, `item`
- **Token bindings**:
  - trigger: `bg-surface-container-high border border-color-border text-fg rounded-DEFAULT`
  - popup: `bg-surface border border-color-border shadow-sm rounded-md`
  - item: `text-sm text-fg hover:bg-surface-container-high`
- **Anti-patterns**:
  - Do not use Material `DropdownButton`; use `Select`.

---

### Combobox

- **File**: `lib/ui/components/combobox/`
- **Class**: `Combobox`
- **Recipe**: `WindSlotRecipe` in `combobox.recipe.dart`
- **Slots**: `trigger`, `popup`, `item`
- **Token bindings**: same as Select, plus debounce search input.
- **Anti-patterns**: same as Select.

---

### SegmentedControl

- **File**: `lib/ui/components/segmented_control/`
- **Class**: `SegmentedControl`
- **Recipe**: `WindSlotRecipe` in `segmented_control.recipe.dart`
- **Variants**:
  - `size`: `sm` | `md`
- **Slots**: `root`, `item`
- **Token bindings**:
  - root: `bg-surface-container rounded-md p-0.5`
  - item active (`selected:`): `bg-surface text-fg shadow-sm rounded-sm`
  - item inactive: `text-fg-muted`
- **Anti-patterns**:
  - Do not use for more than 4-5 options; use `Tabs` or a `Select` instead.

---

### Tabs

- **File**: `lib/ui/components/tabs/`
- **Class**: `Tabs`
- **Recipe**: `WindSlotRecipe` in `tabs.recipe.dart`
- **Slots**: `list`, `tab`, `panel`
- **Token bindings**:
  - list: `border-b border-color-border`
  - tab inactive: `text-fg-muted`
  - tab active (`selected:`): `text-primary border-b-2 border-primary`
  - panel: `pt-4`
- **Anti-patterns**:
  - Do not use Material `TabBar`; use `Tabs`.

---

### Accordion

- **File**: `lib/ui/components/accordion/`
- **Class**: `Accordion`
- **Recipe**: `WindSlotRecipe` in `accordion.recipe.dart`
- **Slots**: `root`, `item`, `header`, `trigger`, `panel`
- **Token bindings**:
  - root: `border border-color-border rounded-md divide-y divide-color-border`
  - trigger: `text-fg font-medium`
  - panel: `text-fg-muted text-sm px-4 pb-4`
- **Anti-patterns**:
  - Do not use for top-level navigation; use for secondary content disclosure only.

---

## Overlays

### Dialog

- **File**: `lib/ui/components/dialog/`
- **Class**: `Dialog`
- **Recipe**: `WindSlotRecipe` in `dialog.recipe.dart`
- **Slots**: `backdrop`, `panel`, `title`, `footer`
- **Token bindings**:
  - backdrop: `bg-fg/50` (semi-transparent fg overlay)
  - panel: `bg-surface rounded-lg shadow-xl max-w-md w-full`
  - title: `text-fg font-semibold text-lg`
  - footer: `flex gap-3 justify-end pt-4`
- **Anti-patterns**:
  - Always use `Dialog.show()` static factory; do not push dialogs as routes.
  - Keep dialog content focused; avoid multi-step flows inside a single dialog.

---

### ConfirmDialog

- **File**: `lib/ui/components/confirm_dialog/`
- **Class**: `ConfirmDialog`
- **Enum**: `ConfirmDialogVariant`
- **Recipe**: `WindSlotRecipe` in `confirm_dialog.recipe.dart`
- **Variants**:
  - `variant`: `primary` | `danger` | `warning`
- **Token bindings**:
  - `danger`: confirm button uses `Button(intent: ButtonIntent.destructive)`
  - `warning`: confirm button uses `Button(intent: ButtonIntent.secondary)` with warning badge
  - `primary`: confirm button uses `Button(intent: ButtonIntent.primary)`
- **Anti-patterns**:
  - Use `danger` for irreversible destructive actions only (account deletion, data wipe).
  - Do not use `warning` for routine confirmation; reserve it for significant but reversible changes.

---

### BottomSheet

- **File**: `lib/ui/components/bottom_sheet/`
- **Class**: `BottomSheet`
- **Recipe**: `WindSlotRecipe` in `bottom_sheet.recipe.dart`
- **Slots**: `backdrop`, `panel`, `handle`, `title`, `footer`
- **Token bindings**:
  - panel: `bg-surface rounded-t-xl`
  - handle: `bg-surface-container-high rounded-full`
- **Anti-patterns**:
  - Respect `SafeArea` at the bottom for home indicator.
  - Do not embed complex multi-step flows; keep to contextual actions.

---

### Toast

- **File**: `lib/ui/components/toast/`
- **Class**: `Toast`
- **Recipe**: `WindRecipe` in `toast.recipe.dart`
- **Variants**:
  - `tone`: `neutral` | `success` | `warning` | `destructive`
- **Token bindings**:
  - `neutral`: `bg-surface border border-color-border text-fg`
  - `success`: `bg-success text-on-primary`
  - `warning`: `bg-warning text-on-primary`
  - `destructive`: `bg-destructive text-on-destructive`
- **Anti-patterns**:
  - Use for non-critical feedback only; critical errors belong in a dialog or inline error state.
  - Auto-dismiss after 4-6 seconds unless action is required.

---

### Tooltip

- **File**: `lib/ui/components/tooltip/`
- **Class**: `Tooltip`
- **Recipe**: `WindSlotRecipe` in `tooltip.recipe.dart`
- **Slots**: `trigger`, `content`
- **Token bindings**:
  - content: `bg-fg text-surface text-xs rounded-md px-2 py-1`
- **Anti-patterns**:
  - Do not use tooltips for essential information; they are invisible on touch devices.
  - WPopover real-click dismiss race is a known issue; do not add Tooltip to interactive paths that require precise tap timing.

---

### DropdownMenu

- **File**: `lib/ui/components/dropdown_menu/`
- **Class**: `DropdownMenu`
- **Recipe**: `WindSlotRecipe` in `dropdown_menu.recipe.dart`
- **Slots**: `trigger`, `panel`, `item`, `separator`
- **Token bindings**:
  - panel: `bg-surface border border-color-border rounded-md shadow-sm`
  - item: `text-sm text-fg hover:bg-surface-container-high`
  - separator: `border-t border-color-border my-1`
- **Anti-patterns**:
  - Do not use for primary navigation (use `Navbar` or `Tabs`).
  - WPopover real-click dismiss race is a known issue; do not regress dismiss behavior.

---

## Structure

### FormField

- **File**: `lib/ui/components/form_field/`
- **Class**: `FormField` (exported as `MagicFormField` to avoid collision with Flutter's `FormField`)
- **Recipe**: `WindSlotRecipe` in `form_field.recipe.dart`
- **Slots**: `root`, `label`, `hint`, `error`
- **Token bindings**:
  - root: `flex flex-col gap-1`
  - label: `text-sm font-medium text-fg`
  - hint: `text-xs text-fg-muted`
  - error: `text-xs text-destructive`
- **Anti-patterns**:
  - Always wrap `Input`/`Textarea` in `MagicFormField`; never render label/error inline.
  - Import as `MagicFormField` to avoid collision with Flutter's `FormField` widget.

---

### PageHeader

- **File**: `lib/ui/components/page_header/`
- **Class**: `PageHeader`
- **Recipe**: `WindSlotRecipe` in `page_header.recipe.dart`
- **Slots**: `title`, `subtitle`, `leading`, `actions`, `inlineActions`
- **Token bindings**:
  - title: `text-xl font-bold text-fg`
  - subtitle: `text-sm text-fg-muted`
- **Anti-patterns**:
  - Do not add navigation chrome inside `PageHeader`; it is a content title, not an app bar.

---

### EmptyState

- **File**: `lib/ui/components/empty_state/`
- **Class**: `EmptyState`
- **Recipe**: `WindSlotRecipe` in `empty_state.recipe.dart`
- **Slots**: `root`, `iconWrap`, `title`, `description`, `action`
- **Token bindings**:
  - iconWrap: `text-fg-disabled`
  - title: `text-fg font-semibold text-lg`
  - description: `text-fg-muted text-sm`
- **Anti-patterns**:
  - Always include a call-to-action in the `action` slot; an empty state without an action is a dead end.
  - Hide filters, tabs, or sorting controls that do not apply when the list is empty.

---

### ErrorState

- **File**: `lib/ui/components/error_state/`
- **Class**: `ErrorState`
- **Recipe**: `WindSlotRecipe` in `error_state.recipe.dart`
- **Slots**: `root`, `iconWrap`, `title`, `description`, `action`
- **Token bindings**:
  - iconWrap: `text-destructive`
  - title: `text-red-700 dark:text-red-400 font-semibold text-lg`
  - description: `text-fg-muted text-sm`
- **Anti-patterns**:
  - Use for unrecoverable states; for recoverable network errors, show a retry button in the `action` slot.

---

### Navbar

- **File**: `lib/ui/components/navbar/`
- **Class**: `Navbar`
- **Recipe**: `WindSlotRecipe` in `navbar.recipe.dart`
- **Slots**: `root`, `item`, `activeItem`
- **Token bindings**:
  - root: `bg-surface border-t border-color-border`
  - item inactive: `text-fg-muted`
  - item active (`selected:`): `text-primary`
- **Anti-patterns**:
  - Limit to 3-5 primary destinations.
  - Do not place secondary actions in the bottom nav; use `DropdownMenu` or a settings page.

---

## Composites

### SocialDivider

- **File**: `lib/ui/components/social_divider/`
- **Class**: `SocialDivider`
- **Token bindings**: `border-color-border text-fg-muted`
- **Anti-patterns**:
  - Use only on auth screens to separate email login from social login options.

---

### NotificationDropdown

- **File**: Composite consuming `DropdownMenu` + `Badge`
- **Token bindings**: inherits from composites.
- **Anti-patterns**:
  - Do not change the `StreamBuilder` unread-count subscription pattern; it is intentional.

---

### UserProfileDropdown

- **File**: Composite consuming `DropdownMenu`
- **Anti-patterns**:
  - Do not add business logic to the dropdown; route to profile/settings views.

---

### TeamSelector

- **File**: Composite consuming `Select` or `DropdownMenu`
- **Anti-patterns**:
  - Keep team-switch callback through `teamResolver`; do not hard-wire team ID.

---

### SectionCard

- **File**: `lib/ui/components/section_card/`
- **Class**: `SectionCard`
- **Token bindings**: `bg-surface-container text-fg-muted`
- **What it is**: one titled group of rows on a screen: the card surface, its `SectionHeader`, and the rows. Replaced eight hand-written copies of the same card className across the two product screens.
- **Anti-patterns**:
  - Do not hand-roll `flex flex-col gap-1 p-4 rounded-lg bg-surface-container` around a `SectionHeader`. That is this component.
  - Do not set `collapsible: true` on the section the user came for. Collapsing costs a tap; it earns its place on an occasional or unbounded section (the attention list, a movement ledger), not on the main content.
  - Do not pass a count of null on a collapsible section. Closed, the count is the only thing telling the user the section is not empty.

---

### FilterChip

- **File**: `lib/ui/components/filter_chip/`
- **Class**: `FilterChip`
- **Token bindings**: `bg-surface-container-high` (idle), `bg-primary-container border-color-border` (applied), `text-fg text-fg-muted`
- **What it is**: one capsule in a filter row. Idle is an offer (a saved filter you could apply); applied is a statement (a criterion narrowing the list now).
- **Anti-patterns**:
  - Do not make the two states look similar. That they are distinguishable at a glance is the whole component; a user who cannot tell reads a filtered list as an empty catalogue.
  - Do not use it as a static tag. That is `Tag`. This one is always tappable and always changes the query.
  - Do not import Material's `FilterChip`. Import `package:flutter/widgets.dart` only, per the material-import rule.

---

### FilterBar

- **File**: `lib/ui/components/filter_bar/`
- **Class**: `FilterBar`
- **Token bindings**: inherits from `FilterChip`; `text-fg-muted` on its text actions.
- **What it is**: the chip row under a list's search field. Two exclusive modes: saved filters when nothing is applied, the active criteria when something is.
- **Anti-patterns**:
  - Do not show both modes at once. Mixing saved filters with active criteria under one treatment is the taxonomy failure documented in `docs/depools-system/features/filtering-and-saved-views.md`.
  - Do not hide it while a filter is applied. An invisible active filter is the documented reason mobile filtering fails.
  - Do not offer "Kaydet" for a filter that already matches a saved one; that is how a short saved list becomes an untrustworthy long one.

---

### DraftField

- **File**: `lib/ui/components/draft_field/`
- **Class**: `DraftField`
- **Token bindings**: `text-fg-muted` (label), `text-fg` (value), `text-ai` (prompt), `MSSkeleton` (loading)
- **What it is**: one field on a product being created, in one of three states: loading, empty because the model could not tell, or filled. Two layouts (`row`, `chip`) share one state machine, because two components with the same three states is how they drift apart.
- **Anti-patterns**:
  - Do not render an unsure field as a plain empty field. The whole point is that "the model gave up" is distinguishable from "optional and skipped"; DESIGN.md's rule is that uncertainty is null, which means empty fields WILL exist.
  - Do not add a confidence number. D31: no consumer product surveyed shows one, and miscalibrated confidence measurably increases trust in wrong answers.
  - Do not use `text-accent` for the prompt. It does not exist, drops silently, and renders at full foreground brightness. Use `text-ai`.
  - Do not give the value `flex-1`. That is a tight fit and shoves the `tahmin` marker to the far edge; `flex-auto min-w-0` lets it wrap and keeps the marker adjacent.

---

### ReceiptLineRow

- **File**: `lib/ui/components/receipt_line_row/`
- **Class**: `ReceiptLineRow`
- **Token bindings**: `text-fg` / `text-fg-muted` / `text-fg-disabled`, `text-ai` (needs attention), `font-mono` (the extracted string)
- **What it is**: one line off a receipt, in one of `receipt_lines`' four resolution states. The extracted string is always shown, in mono, because resolution is a guess about a truncated abbreviation and the paper is the only thing the user can check against.
- **Anti-patterns**:
  - Do not hide the extracted text once a line resolves. "PNR SUT 1LT" is what makes the review checkable.
  - Do not omit the glyph for settled states. Every state gets one and the hierarchy lives in the tone; a half-empty icon column reads as unfinished.
  - Do not make `matched` and `created` look different in weight. Both are settled and the user does not care which; the difference belongs in the meta line.
  - Do not demand a tap per line. `receipt-ingestion.md`'s criterion is a 15-25 line receipt accepted with edits to fewer than 3 lines, so the default is accepted and only exceptions ask.

---

### ScanRow

- **File**: `lib/ui/components/scan_row/`
- **Class**: `ScanRow`
- **Token bindings**: `text-fg` / `text-fg-muted` / `text-fg-disabled`, `text-ai` (needs attention), `font-mono` (the barcode)
- **What it is**: one barcode in a continuous scan batch, in one of `ScanSource`'s five provenance states. The barcode is always shown, in mono, because resolution is a claim about a machine reading and the label in the user's hand is the only check.
- **Anti-patterns**:
  - Do not fold this into `ReceiptLineRow`. It carries PROVENANCE (which stage of the cascade answered), not `receipt_lines.resolution_state`, and a union enum would corrupt the one thing that component is careful about. Two callers is also one short of extracting a shared base.
  - Do not print a source label on every row. D39: silence means the tenant's own inventory, and the annotation goes where trust is lower.
  - Do not show a confidence percentage. D31 again: a named source says how far to trust the row, a number invites arithmetic nobody can act on.
  - Do not let the trailing count and the on-hand figure both render bare. They are two numbers in the same unit on one row; the on-hand one is labelled (`Mevcut: 2 adet`) so it cannot be read as the scan count.

---

### LabelPreview

- **File**: `lib/ui/components/label_preview/`
- **Class**: `LabelPreview` (plus the `SheetTemplate` value class)
- **Token bindings**: `bg-paper`, `bg-ink`, `bg-ink-muted`, `border-color-ink-subtle`, `border-color-border` (the page edge, which IS a UI boundary), `text-fg-muted` (the caption)
- **What it is**: the printed sheet at true A4 proportions, with filled cells drawn as stylised labels and empty cells outlined.
- **Anti-patterns**:
  - Do not express the grid in wind tokens. Core Law 3 forbids interpolating a computed value into a className, so the geometry is `AspectRatio` plus `Expanded` flexes equal to the millimetre figures times ten. Wind paints, Flutter measures.
  - Do not put a raw `Column` inside a wind `flex flex-col` WDiv. The outer sizes to max and hands infinity to a non-flex child, so every `Expanded` in the inner one asserts `RenderBox was not laid out` with nothing naming the cause. The cell slot is padding only.
  - Do not typeset the cells. At sheet scale 9pt is six pixels; use `LabelCard` for legible content.
  - Do not hide empty cells. The waste is the most useful thing the sheet says (D43).

---

### LabelCard

- **File**: `lib/ui/components/label_card/`
- **Class**: `LabelCard`
- **Token bindings**: `bg-paper`, `text-ink`, `text-ink-muted`, `bg-ink`, `text-expired` (the overflow line)
- **What it is**: one label at a legible size: the fields that are enabled, the bars, the code, and the field that will not fit.
- **Anti-patterns**:
  - Do not truncate a name that overruns. `labeling-and-printing.md` requires naming the field instead; truncation looks deliberate in a preview and like a defect on 200 printed labels.
  - Do not theme the card. It is paper (D44); both halves of every pair it uses are the same hex on purpose.
  - Do not give the bars a wind flex container. They are raw `Expanded` widgets and need a plain Flutter `Row`.

---

### LabelItemRow

- **File**: `lib/ui/components/label_item_row/`
- **Class**: `LabelItemRow`
- **Token bindings**: `text-fg` / `text-fg-muted` / `text-fg-disabled`, `bg-surface-container-high` (the stepper buttons), `font-mono` (the code)
- **What it is**: one product in a print batch, with the count and where the count comes from.
- **Anti-patterns**:
  - Do not give a serial-tracked or an already-printed line a stepper. D45: those counts are not the user's to set, and the control is absent rather than disabled because a disabled primary control is visually indistinguishable from a live one here.
  - Do not use `min-h-11` on the stepper buttons. Padding carries the touch target; min-height grows the box without re-centring the glyph.
  - Do not drop a printed line from the list. Criterion 5 makes a partial batch resumable, and a range the user cannot see is a range they cannot name.

---

### ShoppingRow

- **File**: `lib/ui/components/shopping_row/`
- **Class**: `ShoppingRow`
- **Token bindings**: `text-fg` / `text-fg-muted` / `text-fg-disabled`, `text-expiring` and `text-low-stock` (the two reasons with a deadline), `bg-primary` / `text-on-primary` (the tick), `border-color-border` (the empty box)
- **What it is**: one shopping-list line: tick, name, quantity, and why it is there.
- **Anti-patterns**:
  - Do not render a number for a reason that has no forecast behind it. D46: the tier decides the SHAPE of the claim, and a bucket must never become "about 6.5 days".
  - Do not draw a tick inside an unchecked box. The gutter is already reserved by the box itself, so the glyph is free to be conditional; a greyed tick in every empty box makes the list look half-walked, which is the one thing the column exists to answer.
  - Do not replace a ticked line's reason with its state. The section header says where the item is; the reason is what the user checks the quantity against at the shelf.
  - Do not tone every reason. Only the two with a deadline take a status colour, or the list has no priority in it.
  - Do not treat a tick as stock (D47). It means the trolley; the receipt is what writes movements.

---

### ChatMessage

- **File**: `lib/ui/components/chat_message/`
- **Class**: `ChatMessage`
- **Token bindings**: `bg-primary-container` (the user bubble), `text-fg`
- **What it is**: one line of the assistant transcript.
- **Anti-patterns**:
  - Do not give the assistant a bubble. D49: its text is a caption over the component below it, and two facing bubble columns make a work surface read like an instant messenger.
  - Do not uncap the user bubble. A sentence spanning a desktop window puts the reply an eye-movement away.

---

### ChoiceChip

- **File**: `lib/ui/components/choice_chip/`
- **Class**: `ChoiceChip`
- **Token bindings**: `bg-surface-container-high`, `bg-primary-container` (suggested), `text-fg` / `text-fg-muted`
- **What it is**: one tap-answer in an assistant's grouped question card.
- **Anti-patterns**:
  - Do not use `FilterChip` for this. It bakes `'$label filtresini uygula'` into its own `semanticLabel`, so an assistant chip built from it announces something false to a screen reader.
  - Do not omit `semanticLabel`. It is required rather than derived, because a chip in an assistant card can mean anything and a generic label makes an accessible control useless.
  - Do not add a chip that opens another question. `ai-design.md` caps a capture at one grouped card, so every chip has to be a real answer including the skip.

---

### MovementRow

- **File**: `lib/ui/components/movement_row/`
- **Class**: `MovementRow`
- **Token bindings**: `text-in-stock` (inbound), `text-wasted` (waste), `text-fg-muted`, `text-fg-disabled` (the note), `opacity-50` (reversed)
- **What it is**: one entry in the append-only ledger, with its undo affordance. Renders in a product's history, in the activity panel, and in the assistant transcript.
- **Anti-patterns**:
  - Do not build a second movement row for a new surface. Three renderings of one fact are three chances to disagree about it, which is why `action` and `note` are on this component rather than on the panel.
  - Do not hide or collapse a reversed entry. D51: the ledger keeps both rows and the balance only reconciles by hand if both are visible.
  - Do not dim the note along with the row. `text-fg-disabled` under `opacity-50` is unreadable, and the note is the reason the row faded.
  - Do not offer a disabled undo. D52: when the compensating movement would break an invariant, the row states the blocking fact where the button would be.
  - Do not assume the primary line is the reason. In a cross-product feed the product leads; the rule is that the primary line carries whatever separates a row from its neighbours.

---

### OptionRow

- **File**: `lib/ui/components/option_row/`
- **Class**: `OptionRow`
- **Token bindings**: `bg-surface-container-high` (every option), `bg-primary-container` + `border-color-border` (selected), `text-fg`, `text-ai` (the suggestion reason)
- **What it is**: one full-width choice in a picker, with an optional suggestion reason and an optional trailing figure.
- **Anti-patterns**:
  - Do not hand-roll a selectable row. This was extracted at the sixth caller (two in the move sheet, two in the stock-out sheet, one in stock-in, one in the label screen), each of which was a place the "every option gets a fill" rule could drift.
  - Do not drop the fill on unselected options. A group where only the chosen row has a background reads as one highlight among labels, not a set of choices.
  - Do not reach for `min-h-11`. Padding carries the 44pt floor; min-height lands the content 8.5px off centre, measured.
  - Do not render a serial or a code without `isMono`. It is matched character by character against a physical object.

---

### CountRow

- **File**: `lib/ui/components/count_row/`
- **Class**: `CountRow`
- **Token bindings**: `text-fg`, `text-fg-disabled` (uncounted), `text-in-stock` (matched), `text-low-stock` (variance)
- **What it is**: one product being physically counted, in one of three states.
- **Anti-patterns**:
  - Do not show the expected figure before a count is entered. D58: a counter shown "5" looks at a shelf and sees five.
  - Do not default the field to zero, and do not use `0` as its placeholder. An empty field means NOT COUNTED and a zero writes the balance off; this is the one screen where those must not look alike.
  - Do not collapse a two-level count into one decimal. Whole units and an opened amount are two fields, because "1,5 adet" is not verifiable against a shelf.
  - Do not tone the uncounted state. Every row starts uncounted, so a tone there colours the whole screen before the user has done anything.

---

### ShelfCandidateRow

- **File**: `lib/ui/components/shelf_candidate_row/`
- **Class**: `ShelfCandidateRow`
- **Token bindings**: `bg-surface-container-high` (the region badge, which is not tappable), `text-fg`, `text-ai` (unresolved), `text-fg-muted`, `opacity-50` (rejected)
- **What it is**: one region a shelf photograph produced, in one of `LineResolution`'s four states.
- **Anti-patterns**:
  - Do not define a new resolution enum. It shares `LineResolution` with the receipt review because the concept is identical; only the evidence differs (a printed string against a numbered region). `ScanRow` is the opposite case and has its own enum for that reason.
  - Do not omit or reorder the region number. It is the only link to a box on the photograph, so it is fixed-width, mono, and asserted unique and contiguous by test.
  - Do not lead an unresolved row with an empty name. The prompt takes the primary line, as in `ReceiptLineRow`.
  - Do not hide a rejected candidate. A row that vanished on rejection cannot be un-rejected.

---

### QuantityStepper

- **File**: `lib/ui/components/quantity_stepper/`
- **Class**: `QuantityStepper`
- **Token bindings**: `bg-surface-container` + `border-color-border` (the group), `text-fg`
- **What it is**: a typed quantity with minus and plus inside one bordered group.
- **Anti-patterns**:
  - Do not build it as separate bordered boxes. One border owns the whole control; three give three heights and two radii. Neutralise `MSInput`'s own border with `border-0 rounded-none`.
  - Do not reach for a raw `WInput` for an unstyled field. It needs an `Overlay` ancestor and throws a build-phase `setState` from the preview harness.
  - Do not put a stepper on a unit whose granularity is not one. An opened remainder is measured, so plus-one-millilitre cannot reach most of its values; that field stays typed.
  - Do not preview it without callbacks. `WAnchor` gives the pointer cursor only when it has a gesture, so a callback-less preview looks like a missing cursor in working code.

---

### LocationRow

- **File**: `lib/ui/components/location_row/`
- **Class**: `LocationRow`
- **Token bindings**: `text-fg` (name), `text-fg-muted` (empty name, meta, icon)
- **What it is**: one node in the location tree: own name, subtree product count, depth by indent.
- **Anti-patterns**:
  - Do not show the full path here. The ancestors are on screen above; `LocationStockRow` is the one that shows a path, because there the tree is absent.
  - Do not render the icon conditionally. The gutter is reserved on every row, or a parent's icon pushes its name further right than its child's indent and the tree reads inverted.
  - Do not interpolate the indent class (`pl-${depth * 3}`). Wind caches on the literal string and an unknown value drops silently; the depths are a switch over literal tokens, capped at the schema's 6.
  - Do not hide an empty location. It is still a valid destination for a stock-in; it recedes to `text-fg-muted` instead.

---

### ListFooter

- **File**: `lib/ui/components/list_footer/`
- **Class**: `ListFooter`
- **Token bindings**: `text-fg-muted`, `text-fg`, `MSSkeleton`
- **What it is**: the bottom of a cursor-paginated list, in one of three states: a page in flight, the end, or a failed page.
- **Anti-patterns**:
  - Do not let the three states look alike. A list that silently stops is indistinguishable from one that finished, and a failed page showing nothing looks like the end of the data.
  - Do not use a spinner. Skeleton rows as many as the page size, so the incoming rows' space is reserved and the list does not jump.
  - Do not omit the total in the end state. It is the unique-SKU count the plan meters on, so it is the one number worth having there.
  - Do not render it on a list that cannot page. A footer that never fires trains the user to ignore the bottom of the list; state the total instead.

---

## Anti-patterns (global)

| Anti-pattern | Category | Fix |
|-------------|----------|-----|
| Raw `Color(0xFF...)` or `Colors.*` in recipe or widget | Token violation | Use semantic alias (e.g. `bg-primary`) |
| Hardcoded pixel margin (`SizedBox(height: 13)`) | Spacing violation | Use Wind spacing utilities on the 4px scale |
| Multiple preview classes in one file | Preview structure | One `*.preview.dart` per component |
| Exporting preview class from `index.dart` | Preview boundary | `previews:refresh` discovers `*.preview.dart` directly |
| Importing `package:fluttersdk_wind/src/...` directly | Import convention | Use `package:magic/magic.dart` (re-exports wind) |
| Using Material `Switch`, `Checkbox`, `Radio`, `TabBar` | Primitive collision | Use the project component equivalents |
| CSS-only Wind utilities (`box-shadow`, `filter`, `transform`) | Wind unsupported | Use Flutter animation APIs |
| `Icons.*` inline in widget body | Tree-shaking | Extract as `static const IconData _icon = Icons.x;` |
| Missing `dark:` on any color token | Dark parity | Every alias expands to a light+dark pair |
