---
applyTo: "lib/**"
---

<!-- GENERATED from .claude/rules/design.md by bin/sync-instructions. Edit that file, not this one. -->

<!-- Trimmed on 2026-08-11 from 258 lines: the copy and i18n sections moved to flutter-app.md, the alias table collapsed, and every anti-pattern row tightened to the fact plus the fix. It still runs past the 40-to-80-line sweet spot, and the anti-pattern table is why: each row is one defect that reached a screenshot, several of them twice. Cutting a row does not save tokens, it re-buys the debugging cycle. -->

# Design rules (UI surface)

Applies to `lib/`. `DESIGN.md` owns the token VALUES, `docs/component-registry.md` owns what exists, and `.github/instructions/flutter-app.instructions.md` owns the copy. This file is the component contract and the defects that keep recurring.

## Three places this app overrides wind-ui

`wind-ui` is the standard for every className written here and a copy of it sits at `.github/skills/wind-ui/SKILL.md`. Three of its rules do not hold in this app, and each is a rule an agent following the skill correctly would apply and be wrong.

- **Do NOT write a `dark:` peer.** The skill's Core Law 2 asks for one on every colour token, and that is right for a raw palette token. Every colour here is a semantic alias that ALREADY expands to a `'<light> dark:<dark>'` pair, so `dark:bg-surface` re-applies the prefix over a value that carries its own and produces nothing. Write `bg-surface` alone.
- **The touch-target floor is 44, not 48.** The skill says an icon button needs 48 dp; `DESIGN.md` says 44x44, following Apple rather than Material, and `DESIGN.md` wins because it is the source `design:sync` reads. Pad invisibly to reach it rather than growing the visual control.
- **No raw palette token.** Every example in the skill styles with `bg-gray-800` and `text-blue-600`. Those parse here and are a build failure: `bin/design-tokens` allows only the semantic aliases below. Translate the skill's shape, never its colours.

Everything else in the skill applies unchanged, including the one this app is currently behind: a scrollable root needs `scrollPrimary: true`, and nothing here sets it.

## Atomic component folder contract

```
lib/ui/components/<name>/
  <name>.dart           # class <Name> extends StatelessWidget, @immutable
  <name>.recipe.dart    # WindRecipe or WindSlotRecipe
  <name>.preview.dart   # ONE preview widget rendering every variant x state
  index.dart            # exports <name>.dart + <name>.recipe.dart, NOT the preview
```

Folder and file names are `lower_snake_case`; the class is unprefixed `UpperCamelCase`. `previews:refresh` finds components by scanning `*.preview.dart`, one preview class per file. Scaffold with `dart run bin/dispatcher.dart make:component <Name> [--variants=intent,size] [--slots]`.

## WindRecipe

All variant logic lives in a `WindRecipe`, or a `WindSlotRecipe` for slot-based components. Emission order is always `base ++ variant (definition order) ++ compound ++ caller`: never sort, never deduplicate. Variant values are strings matching the map keys, and `null` clears a default. The caller's `className` appends last, so it can override variant output at the same granularity. Import `WindRecipe` from `package:magic/magic.dart`, which re-exports the wind barrel; a direct `package:fluttersdk_wind/...` import trips `depend_on_referenced_packages`.

## Token-only rule

Every colour goes through a semantic alias key. No raw hex, no `Color(0xFF...)`, no `Colors.*` in component or view code, and `bin/design-tokens` fails the build on one outside `.design-token-allowlist`.

`design:sync` emits a FIXED table of 17 aliases and silently drops anything else: `bg-surface`, `bg-surface-container`, `bg-surface-container-high`, `text-fg`, `text-fg-muted`, `text-fg-disabled`, `bg-primary`, `text-on-primary`, `bg-primary-container`, `bg-accent`, `border-color-border`, `border-color-border-subtle`, `bg-destructive`, `text-on-destructive`, `bg-destructive-container`, `bg-success`, `bg-warning`. The status, paper, overlay and control families are hand-authored supplements under `lib/config/depools_*_tokens.dart`, merged into the alias map in `lib/main.dart`.

Each alias already expands to a `'<light> dark:<dark>'` pair, so write `bg-surface` alone; adding `dark:bg-surface` is nonsense. Two silent drops to know about, both documented in `DESIGN.md`: `text-accent` does not exist (only `bg-accent` is emitted, so tinted text uses a status family such as `text-ai`), and `border-<bg-token>` finds nothing, so `border-bg-primary` makes the border vanish with no warning.

To add or change a token: edit `DESIGN.md`, then `dart run bin/dispatcher.dart design:sync`.

## Both appearances, every time

**A screen is not verified until it has been seen in light AND dark.** The two appearances are not brightness variants of each other: elevation direction inverts, so a token pair that is correct in one can be actively wrong in the other, and no amount of care in dark mode surfaces it. This was skipped for seven consecutive screens in one session, and the light-mode defect that came out of it (an interactive fill reading as disabled) had shipped across six of them.

```sh
# Confirm the mode actually changed before trusting the screenshot: the tap sometimes does not land.
# --grep keeps the matching node plus the ancestors carrying its ref, so this costs a few lines
# rather than the whole tree, and the tap's own `effect` block reports whether anything changed.
./bin/fsa dusk:snap --grep='Toggle theme'
./bin/fsa dusk:tap --ref=eN
./bin/fsa dusk:screenshot -o /tmp/light.jpg
python3 -c "from PIL import Image; px=Image.open('/tmp/light.jpg').convert('RGB').getpixel((1200,300)); print('DARK' if sum(px)<200 else 'LIGHT')"
```

## Preview-required

No component ships without a preview covering every variant and state. After adding or changing one, run `previews:refresh`, navigate with `./bin/fsa dusk:navigate --route=/preview`, take light and dark screenshots, and run the `component-visual-reviewer` agent before calling it ship-ready.

## Material import discipline

A component sharing a name with a Material widget (`Card`, `Switch`, `Badge`, `Tooltip`, `Checkbox`) imports `package:flutter/widgets.dart`, plus `package:flutter/material.dart' show Icons` only when icons are needed. Never a bare `material.dart` import. Build on Wind W-widgets inside component bodies.

## Anti-patterns

Each is a blocker and the `component-visual-reviewer` flags it. The numbers are measured, not estimated.

| Anti-pattern | Correct approach |
|---|---|
| `Color(0xFF...)` or `Colors.*` in component code | A semantic alias key |
| Hardcoded pixels (`SizedBox(height: 13)`) | Wind spacing utilities on the 4px scale |
| A one-off widget when a library component exists | Check `docs/component-registry.md` first |
| `Icons.*` inline in a component body | `static const IconData _icon = Icons.x;` |
| `min-h-11` on an `MSButton` to reach 44pt | Padding: `py-3` on `md`, `py-3.5` on `sm`. Min-height grows the box downward without re-centring the label, measured 4 logical px high. Check the arithmetic against the SIZE: `py-3` on an `sm` button lands at 40 and misses the target. `min-h-11` is still correct on a plain `WDiv` |
| Two controls in one row, each sized by its own padding | Pin both to the same explicit height (`h-11`). A row reads as one control, so `items-center` centres the MISMATCH: the stock search field measured 52 and its filter button 44 |
| A `Material`-free overlay mounted OUTSIDE the app shell | Wrap in `Material(type: MaterialType.transparency)` and let a wind `bg-surface` box paint the fill. Outside `layout.app` the `Material` ancestor is gone and every string renders in Flutter's yellow double-underlined fallback, which looks like a font bug and sends you into `wind_theme.g.dart` |
| `Column` + `Expanded` inside a page, to pin a footer | Anchor from OUTSIDE `layout.app` (`ui/layouts/page_chrome.dart`). The shell hands every route unbounded height, so `Expanded` fails as `RenderBox was not laid out`, which names nothing. Same fact means a page-mounted `Positioned` anchors to the scrolled content rather than the viewport: renders nothing, throws nothing |
| Anything a screen exists for, placed BELOW a list that grows without bound | A setting MOVES to `/settings` with a folded shortcut above the list; an action gets PINNED via `AppPageScaffold`'s `footer:`. An unbounded list has no bottom, so what sits under it is unreachable for exactly the user with enough rows to need it. Found on locations, present on six (D70) |
| A viewport-anchored control overlapping another | Measure, do not guess. The chrome host folds the pinned footer's measured height into `MediaQuery.padding.bottom`. A constant is wrong by construction when the footer is two lines on one screen and one button on another. The nav has no fixed height either (measured 62 logical px), so clear it by overlapping its hairline |
| A conditionally-rendered leading glyph OR trailing control | Reserve the gutter with a fixed-size box and put the glyph inside. Text that shifts per row destroys the alignment the layout carries. Cost two fixes in one session: a ragged receipt list, and a location tree where children appeared LEFT of their parents. Carry state in TONE instead. The trailing edge is easier to miss: an opened-unit field rendered only for some products put every field at a different x. Give the labels FIXED widths too, or `adet` and `ml` move the column |
| `relative` plus an `absolute` child on the SAME `WDiv` as the flex alignment | Split the layers: an outer `relative` box holding the flex panel and the overlay as two children. Wind turns a container with a positioned child into a Stack, and a Stack silently ignores `items-center justify-center` |
| A raw `Expanded` or a nested `Column` inside a wind `flex` WDiv | Let one layer own the main axis. Put raw `Expanded` children in a plain `Row`/`Column` and give the surrounding WDiv paint-only tokens (`h-8`, `px-1`). Both failures read as `RenderBox was not laid out` |
| `items-stretch` on a Row inside a scrolling Column | `items-start`. The Row has no height there, so stretch asks children to match a height that does not exist |
| `bg-surface-container-high` as the fill of anything TAPPABLE | Card tone plus a hairline: `bg-surface-container border border-color-border`. That token is DESIGN.md's INPUT background: `#2C2C2E` on a `#1C1C1E` sheet reads as raised, `#E5E5EA` on `#FFFFFF` reads as recessed, which is the universal look of a disabled control. Elevation direction FLIPS between appearances, so no fill can carry "pressable" in both; a border can |
| Selection carried by fill tint alone | Add a non-colour signal: a radio dot, a tick, a glyph. White on `#E3ECFF` is subtle in light and nothing at all to a colour-blind user |
| Controls sized to their content when the row repeats down a list | Fixed widths. A list of rows is a TABLE even when built from flex boxes. If a control is absent on some rows, reserve its space |
| An enabled INPUT left on `bg-surface-container-high` | Pass `className: 'bg-surface-container'`. MSInput ships the input tone, `#E5E5EA` on a white card, and its hairline is too close in value to rescue it |
| A control whose buttons have no callback, previewed that way | Wire the callbacks and sweep EVERY preview, not the reported one. `WAnchor` gives the pointer cursor only with a real gesture, so the catalog showed a dead control for a third of the library. Since wind 1.5 it emits no `Semantics(button: true)` either without a gesture or a `semanticLabel`, so the control is invisible to a dusk snapshot as well as to a screen reader. Use `static void _noop() {}` rather than `() {}`, which is not a constant and breaks every `const` in the file |
| A stepper built as separate boxes in a row | ONE border around the whole control with hairline dividers inside, the segmented shape iOS and Material both use. Neutralise `MSInput`'s border and radius from the caller with `border-0 rounded-none`. Do NOT reach for a raw `WInput`: it needs an `Overlay` ancestor and throws a build-phase `setState` from the preview harness |
| A stepper whose step does not match its unit's granularity | No stepper. `±1` belongs on a countable unit; an opened remainder is a measured amount, so that field stays typed |
| A generic bar as a loading placeholder | The placeholder is the ROW's shadow: same component, same geometry, so the list cannot jump when content lands (`ProductRow.skeleton()`) |
| `h-full` on a route's root | The shell wraps a route in a vertical scroll, so `h-full` resolves to infinity and wind asserts by name. A screen needing a bounded region computes it from `MediaQuery`, clamped at both ends |
| Previewing a bounded-height screen with `PreviewChrome.none` | Use `appMobile`. `none` hands the view infinity, and `appDesktop` bounds the height but LIES about the width (a wide MediaQuery inside a narrow pane), which overflowed a composer row by 107px |
| A selectable option with no fill when unselected | Give every option a `bg-surface-container-high`; otherwise the group reads as one highlight among labels |
| Several preview classes in one `.preview.dart` | One preview class per file |
| CSS-only Wind utilities (`box-shadow`, `filter`, `transform`, `group-*`) | Unsupported in wind; use Flutter animation APIs |
| Hand-editing `lib/config/wind_theme.g.dart` | `dart run bin/dispatcher.dart design:sync` |
| Reading a low-contrast FILL as a 1.4.11 failure when the control has visible text | Check for text or an icon first. W3C's Understanding of 1.4.11 exempts a control with visible content, so `MSButton`'s secondary fill at 1.31:1 is NOT a failure. A switch is the opposite case: its track and thumb ARE the whole control |
| A `magic_starter` control used with no `className`, reviewed in dark only | Pass `className: 'border border-color-control'` on anything whose SHAPE is carried by a fill, and check it in light. `MSSwitch`'s off track measured 1.21:1 on a white card while dark mode looked perfect. `border-color-border` only reached 1.67:1; `border-color-control` is the token for a control's edge |
| A row of badges or tags with no `wrap` | `flex flex-row wrap`. The count is variable by definition, so no width is known to fit. `LotRow`'s meta line overflowed by 16 to 36px at 390px |
| `truncate` on a `WText` inside a Row, expecting it to shrink | It sets ellipsis overflow and nothing else, so the Text keeps its intrinsic width and the ellipsis never appears. Pair with `flex-1 min-w-0` on the shrinkable child and `shrink-0` on the one keeping its width |
| Verifying a list screen at catalog width only | Add a `PreviewChrome.appMobile` phone preview. Every list screen was verified wide only, so its densest row had never been laid out at 390px |
| A `WDiv` styled to LOOK like a control | Build the control. Two screens carried a magnifier plus a `WText` in an input-toned box: pixel-identical to a search field, with no gesture at all |
| A second preview file for a second width | `ResponsiveScreenPreview` renders both in ONE preview: the width is a VARIANT. Fourteen `*PhoneScreen` files were added before this was named. Every screen still has to be seen at 390px in the FIXED frame, because the catalog keeps its sidebar and narrowing squeezes the harness instead of the screen |
| A row of `shrink-0` columns with no narrow arrangement | `flex flex-col md:flex-row` at a group boundary. When every child is `shrink-0`, nothing can give. Reserve the empty columns with `hidden md:flex` |
| A className that BRANCHES on a value: `'bg-${on ? "primary" : "surface"}'` | `states:` plus prefixed classes: a static className carrying `selected:bg-primary`, and `states: on ? const {'selected'} : const {}`. Branching mints a cache key per value and the prefix system stops applying. Interpolation itself is not the defect and four call sites here do it correctly, composing a `WindSlotRecipe` slot or a token-returning helper (`'${slots['icon']} ${locationGlyphClassName(colour)}'`); that is how a slot recipe is meant to be consumed. Read what is being interpolated before calling it a violation |
| `overflow-y-auto` with no `scrollPrimary: true` | Add the constructor prop. There is no className for it, so iOS tap-to-top is silently dead. Nothing in this app sets it yet |
| A `WCheckbox`, `WRadio` or `WSwitch` with a null `onChanged` | Pass a callback, or pass `disabled: true` and mean it. As of wind 1.5 a null callback renders the control display-only exactly like `disabled: true`: no tap, reported as not enabled, `disabled:` styles active. It looks like a live control and reads to dusk as a dead one |
| `justify-between` on a row that also has a `flex-1` child | Pick one. A grow claim turns off `justify-*`'s shrink wrap, so `flex-1` keeps the whole remainder and the siblings sit at content width against it. The even split you were reaching for never happens |
| Trusting a clean `dusk:exceptions` after re-navigating | Flutter announces an overflow ONCE per `RenderFlex` instance, so it appears on the first paint after a hot restart and never again. Restart, then navigate, then read. The buffer is cumulative, so clear it between routes with `dusk:exceptions --clear`, which returns everything so far and empties dusk's own buffer; each reading is then a delta instead of a running total |

## Release boundary

`*.preview.dart` and the generated `lib/_previews.g.dart` are dev-only, excluded from release builds through the `magic_devtools` boundary and the `kDebugMode` const-fold. Never import a preview file from production code.
