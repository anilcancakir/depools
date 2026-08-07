---
applyTo: "lib/**"
---

<!-- GENERATED from .claude/rules/design.md by bin/sync-instructions. Edit that file, not this one. -->

# Design Rules (UI surface)

These rules apply whenever you touch any file under `lib/`. They complement `.github/copilot-instructions.md` with the implementation-level specifics.

## Atomic Component Folder Contract

Every component in the `magic_starter` generic library lives in a 4-file atomic folder:

```
lib/ui/components/<name>/
  <name>.dart           # class <Name> extends StatelessWidget, @immutable
  <name>.recipe.dart    # WindRecipe or WindSlotRecipe
  <name>.preview.dart   # ONE preview widget rendering all variant x state combos
  index.dart            # exports <name>.dart + <name>.recipe.dart (NOT preview)
```

- Folder and file names are `lower_snake_case` (dotted suffixes `.recipe.dart`/`.preview.dart` are valid).
- Component class name is unprefixed `UpperCamelCase` (`card.dart` -> `class Card`).
- `index.dart` exports the component class, variant enums, and the recipe. Never export the preview file (it is dev-only).
- `previews:refresh` discovers components by scanning `*.preview.dart` files. One preview class per file, no exceptions.

To scaffold: `dart run bin/dispatcher.dart make:component <Name> [--variants=intent,size] [--slots]`

## WindRecipe Usage

All variant logic lives in a `WindRecipe` (or `WindSlotRecipe` for slot-based components):

```dart
final myRecipe = WindRecipe(
  base: 'flex items-center gap-2',
  variants: {
    'intent': {
      'primary': 'bg-primary text-on-primary',
      'secondary': 'bg-surface-container text-fg border border-color-border',
      'ghost': 'text-fg',
    },
    'size': {
      'sm': 'px-3 py-1.5 text-xs',
      'md': 'px-4 py-2 text-sm',
      'lg': 'px-5 py-2.5 text-base',
    },
  },
  defaultVariants: {'intent': 'primary', 'size': 'md'},
);
```

- Emission order is always: `base ++ variant (definition order) ++ compound ++ caller`. Never sort or deduplicate.
- Pass variant values as strings matching the map keys. Pass `null` to clear a default.
- The caller `className` argument appends last; it can override variant output at the same granularity.
- Import `WindRecipe` via `package:magic/magic.dart` inside `magic_starter` files (it re-exports the wind barrel). Direct `package:fluttersdk_wind/...` imports trip `depend_on_referenced_packages`.

## Token-Only Rule

All colors go through semantic alias keys defined in `DESIGN.md`. Never use raw hex, `Color(0xFF...)`, or `Colors.*` in component or view code.

The 17 semantic alias keys:

| Key | Role |
|-----|------|
| `bg-surface` | Page background |
| `bg-surface-container` | Card, panel background |
| `bg-surface-container-high` | Input background, nested panels |
| `text-fg` | Primary text |
| `text-fg-muted` | Secondary text |
| `text-fg-disabled` | Disabled/meta text |
| `bg-primary` | Brand action background |
| `text-on-primary` | Text on brand action surface |
| `bg-primary-container` | Tinted brand surface |
| `bg-accent` | Secondary accent |
| `border-color-border` | Dividers, card borders |
| `border-color-border-subtle` | Hairline borders |
| `bg-destructive` | Danger action background |
| `text-on-destructive` | Text on danger surface |
| `bg-destructive-container` | Tinted danger surface |
| `bg-success` | Success tone |
| `bg-warning` | Warning tone |

Each alias already expands to a `'<light> dark:<dark>'` pair, so write `bg-surface` on its own; adding `dark:bg-surface` is nonsense. An explicit `dark:` is only ever needed for a raw arbitrary value, which the rule above already bans.

To add or change a semantic token: edit `DESIGN.md` and run `dart run bin/dispatcher.dart design:sync`.

## Both appearances, every time

**A screen is not verified until it has been seen in light AND dark.** This is already in
the `design-first-workflow` skill and it was skipped for seven consecutive screens in one
session; every one of them was reviewed in dark mode only, and the light-mode defect that
came out of it (an interactive fill reading as disabled) had shipped across six of them
before Anılcan spotted it in a single glance.

The reason it needs to be a hard gate rather than a good habit: the two appearances are not
brightness variants of each other. Elevation direction inverts, so a token pair that is
correct in one can be actively wrong in the other, and no amount of care in dark mode will
surface it.

```sh
# Toggle from the catalog header, then confirm the mode actually changed before trusting
# the screenshot: the tap sometimes does not land.
./bin/fsa dusk:snap | grep 'Toggle theme'
./bin/fsa dusk:tap --ref=eN
./bin/fsa dusk:screenshot -o /tmp/light.jpg
python3 -c "from PIL import Image; px=Image.open('/tmp/light.jpg').convert('RGB').getpixel((1200,300)); print('DARK' if sum(px)<200 else 'LIGHT')"
```

## Preview-Required Rule

No component ships without a preview widget.

- The preview file (`<name>.preview.dart`) must render every variant x state combination so the catalog shows the full range.
- After adding or modifying a preview, regenerate the catalog: `dart run bin/dispatcher.dart previews:refresh`
- Verify dark/light parity by navigating to `/preview` in debug mode: `./bin/fsa dusk:navigate --route=/preview`
- Take light and dark screenshots and run the `component-visual-reviewer` agent (a Claude Code agent definition; Copilot has no equivalent, so apply those criteria by hand) before marking a component ship-ready.

## Material Import Discipline

Component files that share a name with a Material widget (`Card`, `Switch`, `Badge`, `Tooltip`, `Checkbox`, etc.) must import Flutter as:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart' show Icons;  // only if icons are needed
```

Never `import 'package:flutter/material.dart'` without `show`. Build exclusively on Wind W-widgets inside component bodies.

## Turkish UI copy

The app's copy drifted conversational and Anılcan called it: "Bu ne? dokunup eşleştir" for a line that could not be resolved, "modelden gelmedi, sen yaz" for an empty field, "kendi kodun, istersen yaz" for an optional one. Each reads like a person talking over your shoulder rather than a product telling you where things stand.

Three rules, and they are enough:

**Buttons are imperative.** `Kaydet`, `Çıkar`, `Ekle`, `Vazgeç`, `Filtreyi temizle`. This is the one place a command belongs, because the user is about to issue one.

**States are nominal.** `Eşleştirilemedi`, not "Bu ne? dokunup eşleştir". `Belirlenemedi`, not "modelden gelmedi, sen yaz". `İsteğe bağlı`, not "kendi kodun, istersen yaz". `Takip edilmiyor`, `Atlandı`, `Yeni ürün`, `Kalan: 2 adet`. A state describes the world; it does not ask for anything.

**Never the familiar singular.** No `sen yaz`, `istersen`, `tararsan`, `dokun`, `belirle`. Where an instruction is genuinely unavoidable, use the formal plural (`kaldırın`, `temizleyin`, `dokunun`) and keep it in a description or a semantic label, never in a field's own value.

Two consequences worth stating:

- **Do not tell the user to tap.** The row is tappable; saying `dokunup eşleştir` explains a touchscreen. Affordance carries the action, the label carries the state. `semanticLabel` is the exception, because a screen reader has no affordance to feel.
- **`otomatik`, not `tahmin`.** An inferred value was derived from the name, the barcode or the category. "Guess" understates the mechanism and invites less trust than it deserves.

## Anti-Patterns

Each of these is a blocker, and the `component-visual-reviewer` flags every one.

| Anti-pattern | Correct approach |
|-------------|-----------------|
| `Color(0xFF...)` or `Colors.*` in component code | A semantic alias key from the table above |
| Hardcoded pixels (`SizedBox(height: 13)`) | Wind spacing utilities on the 4px scale |
| A one-off widget when a library component exists | Check `docs/component-registry.md` first |
| `Icons.*` inline in a component body | Extract as `static const IconData _icon = Icons.x;` |
| `min-h-11` on an `MSButton` to reach the 44pt target | Use padding (`py-3` on `md`). Measured: min-height grows the box downward without re-centring the label, 4 logical px high. `min-h-11` is still correct on a plain `WDiv`. |
| **Any conditionally-rendered leading glyph OR trailing control** (per state, per row, per depth) | Always reserve the gutter with a fixed-size box and put the glyph inside it. A conditional icon shifts the text beside it, and text that shifts per row destroys the alignment the layout was carrying. This cost two separate fixes in one session: a receipt list with a ragged left edge, and a location tree where children appeared LEFT of their parents because the parent's icon pushed its name further right than the child's indent. Carry state in TONE instead: settled rows `text-fg-disabled`, the one needing attention `text-ai`. **The same failure happens on the trailing edge and it is easier to miss**: a count row rendered its opened-unit field only for products that have one, so every field in the list sat at a different x. Reserve the column with an empty box of the same width. Give the labels beside a column FIXED widths too, or `adet` and `ml` move the column by the difference in their text. |
| `relative` plus an `absolute` child on the SAME `WDiv` as the flex alignment | Split the layers: an outer `relative` box holding the flex panel and the positioned overlay as two children. Wind turns a container with a positioned child into a Stack, and a Stack silently ignores `items-center justify-center`, so the content collapses to the top-left of an otherwise correct-looking panel. |
| A raw Flutter `Expanded` or a nested `Column` inside a wind `flex` WDiv | Let one layer own the main axis. Wind paints, Flutter measures: put raw `Expanded` children in a plain `Row`/`Column` and give the surrounding WDiv paint-only tokens (`h-8`, `px-1`). Wind's flex box does not give a bare `Expanded` the parent it needs, and a `Column` nested in wind's `Column` is handed unbounded height. Both fail as `RenderBox was not laid out`, which names nothing. |
| `items-stretch` on a Row inside a scrolling Column | `items-start`. The Row has no height of its own there, so stretch asks its children to match a height that does not exist and asserts, again without naming the Row. |
| `bg-surface-container-high` as the fill of anything TAPPABLE (an option row, a chip, a stepper button) | Card tone plus a hairline: `bg-surface-container border border-color-border`. That token is DESIGN.md's INPUT background. Measured: it is `#2C2C2E` on a `#1C1C1E` sheet in dark (lighter than its container, reads as raised, so tappable) and `#E5E5EA` on `#FFFFFF` in light (darker than its container, reads as recessed, which is the universal look of a disabled control). **Elevation direction flips between appearances**, so no fill token can carry "pressable" in both; a border can. Anılcan caught this in one glance at a light-mode screenshot after it had shipped across six screens. Keep the input tone for actual input wells, non-tappable panels and placeholder thumbs. |
| Selection carried by fill tint alone | Add a non-colour signal: a radio dot, a tick, a glyph. White against `#E3ECFF` is a subtle difference in light mode and no difference at all to a colour-blind user, and DESIGN.md's "colour never carries meaning alone" applies to state, not only to status. |
| A row of controls sized to their content when the row repeats down a list | Fixed widths. A list of rows is a TABLE even when it is built out of flex boxes, and a column that moves per row is unreadable. If a control is absent on some rows, reserve its space rather than dropping it. |
| An enabled INPUT left on `bg-surface-container-high` | Pass `className: 'bg-surface-container'`. MSInput ships the input tone, which on a `#FFFFFF` card is `#E5E5EA`: darker than its container, and its `border-color-border` hairline is too close in value to rescue it, so an enabled field reads as disabled. Anılcan caught this after the options and the chips; it is the same root cause a third time. |
| A control whose buttons have no callback, previewed that way | Wire the callbacks in the preview. `WAnchor` gives the pointer cursor only when it actually has a gesture, so a preview that omits them shows no hand on hover and reads as a missing cursor in working code. That is how one was reported. |
| A stepper built as separate boxes in a row | ONE border around the whole control, with the buttons and field inside it and hairline dividers between them (the segmented shape iOS and Material both use). Neutralise `MSInput`'s own border and radius from the caller with `border-0 rounded-none`, which works because wind ships a `0` border width and a `none` radius. Do NOT reach for a raw `WInput` to get an unstyled field: it needs an `Overlay` ancestor and throws a build-phase `setState` from the preview harness. Three shapes were tried before this one. |
| A stepper whose step does not match its unit's granularity | No stepper. `±1` belongs on a countable unit; an opened remainder is a measured amount where plus-one-millilitre cannot reach most of its own values, so that field stays typed. |
| A selectable option with no fill when unselected | Give every option a `bg-surface-container-high`; a group where only the selected row has a background reads as one highlight among labels, not a set of choices |
| Several preview classes in one `.preview.dart` | One preview class per file |
| CSS-only Wind utilities (`box-shadow`, `filter`, `transform`, `group-*`) | Unsupported in wind; use Flutter animation APIs |
| Hand-editing `lib/config/wind_theme.g.dart` | `dart run bin/dispatcher.dart design:sync` |
| Shipping a component with no preview | Add the preview, run `previews:refresh` |

## Release Boundary

Preview files (`*.preview.dart`) and the generated `_previews.g.dart` are dev-only. They are excluded from release builds through the `magic_devtools` dev-package boundary and `kDebugMode`/`kReleaseMode` const-fold. Never import a preview file from production code.
