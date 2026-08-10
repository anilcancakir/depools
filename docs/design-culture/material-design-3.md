# Material Design 3 / Material You (Flutter/Wind reference)

Read this before building a screen in Google's design language. It is a decision tool first,
spec second. This doc maps M3 concepts onto Flutter's `ThemeData`/`ColorScheme` and the Wind
semantic token ROLES.

> **This file names roles, never values.** M3's own numbers appear where they are M3's (the 600dp
> navigation thresholds, the shape scale's canonical radii); this app's numbers do not appear at all.
> `DESIGN.md` is the authority on what this palette is and where it diverges from M3 on purpose,
> `.claude/rules/design.md` on how it is applied, `docs/component-registry.md` on what exists.

## When to choose this language

Choose Material when:

- Building for Android / Wear OS, or cross-platform apps that should feel at home on Google
  devices.
- The domain is data-dense or tool-heavy (dashboards, forms, settings): Material's explicit
  density and component set fit.
- You need robust light/dark plus accessible contrast without per-component tuning; the role
  system gives it for free.
- The brand tolerates a colorful, rounded, springy aesthetic.

Avoid it when:

- You want a restrained, content-first Apple feel; see [apple-hig.md](apple-hig.md).

## Core idea

Material 3 is token-driven: components reference semantic ROLES, never raw hex. A single seed
color generates tonal palettes via the HCT color space; roles map specific tones to slots and
remap for dark mode automatically.

In Flutter this is `ColorScheme.fromSeed(seedColor: ...)` plus `ThemeData.colorScheme`. In this
codebase, `design:sync` generates a `WindThemeData` from `DESIGN.md` and seeds a 50-900 ramp from the
`primary` light hex, which `toThemeData()` uses for Material interop. Which hue that is, and why, is
`DESIGN.md`'s business. See `lib/config/wind_theme.g.dart` for the generated result, and never edit
it.

## Mapping M3 roles to the 17 Wind semantic tokens

The 17 semantic alias keys in DESIGN.md align to M3 roles. Use the Wind token in `className`;
Flutter's `ColorScheme` resolves the equivalent role for Material widget sub-trees.

| M3 role | Wind token | Usage |
|---|---|---|
| `surface` | `bg-surface` | Page canvas |
| `surface-container` | `bg-surface-container` | Cards, sheets |
| `surface-container-high` | `bg-surface-container-high` | Input backgrounds, nested panels |
| `on-surface` | `text-fg` | Primary body text |
| `on-surface-variant` | `text-fg-muted` | Secondary/helper text |
| (disabled) | `text-fg-disabled` | Disabled labels |
| `primary` | `bg-primary` | Primary action fills |
| `on-primary` | `text-on-primary` | Text on primary fills |
| `primary-container` | `bg-primary-container` | Tonal button fills, badge backgrounds |
| (secondary accent) | `bg-accent` | Secondary emphasis fills |
| `outline` | `border-color-border` | Interactive borders, input outlines |
| `outline-variant` | `border-color-border-subtle` | Decorative dividers |
| `error` | `bg-destructive` | Error/danger fills |
| `on-error` | `text-on-destructive` | Text on error fills |
| `error-container` | `bg-destructive-container` | Error container backgrounds |
| (success) | `bg-success` | Success state fills |
| (warning) | `bg-warning` | Warning state fills |

Always pair a role with its `on-*` token (for example `bg-primary text-on-primary`). Mixing
families breaks the guaranteed contrast.

### Using tokens in Wind className

```dart
// Roles in a className. Take the actual component from the registry.
WDiv(
  className: 'bg-surface-container rounded-lg p-4 border border-color-border',
  child: ...,
)

// Secondary text
WText('Helper text', className: 'text-fg-muted text-sm')
```

Each alias already expands to a light and dark pair, so write the alias alone. Adding `dark:bg-surface-container`
beside `bg-surface-container` is nonsense.

## Surface depth system

Express elevation with tonal surface-container steps, not drop shadows.

```
surface                  <- page canvas
  surface-container      <- cards, sheets
    surface-container-high  <- input wells, nested panels
```

**The ladder is an ORDER, not a brightness direction.** M3's own example runs light-to-lighter in
light mode, and a palette whose page is darker than its cards runs the other way; both satisfy the
ordering. Getting the direction backwards is a real defect this app has already shipped and fixed, so
read the hex from `DESIGN.md` rather than assuming M3's example.

Two consequences `.claude/rules/design.md` records from measurement: `surface-container-high` is the
INPUT tone, so it must not be the fill of anything tappable, and elevation direction inverts between
appearances, so no fill token can mean "pressable" in both. Reserve shadows for genuinely floating
elements (popovers, modals).

## State layers

Hover, focus, and pressed states overlay the `on-*` color at low opacity:

| State | Opacity |
|---|---|
| Hover | 8% |
| Focus | 10% |
| Pressed | 10% |
| Dragged | 16% |

In Wind/magic_starter components this is expressed as `hover:bg-surface-container` or
`hover:opacity-90` rather than precise opacity math. Only one state layer at a time.

## Navigation by breakpoint

Material specifies navigation component by viewport width:

- Under 600dp: bottom navigation bar (3-5 destinations)
- 600-839dp: navigation rail
- 840dp and above: navigation rail or navigation drawer

`magic_starter`'s `AppLayout` maps this onto ONE breakpoint, and it is not the one M3's thresholds
suggest: read [wind-responsive.md](wind-responsive.md) for which prefix the shell actually switches
on before writing a `hidden`/`flex` pair against it. Guessing costs a whole width's worth of review.

## Typography

M3's roles are Display, Headline, Title, Body and Label, each in three sizes, and the useful part of
the system is the ORDER rather than the names: a Title is heavier than a Body at the same size, and
weight distinguishes them before size does.

This app's scale is in `DESIGN.md`, follows iOS rather than a generic web ladder, and deliberately
gives two steps the same size and different weights. Take the step from there and do not map M3 role
names onto it by hand.

Use weight 500-600 for interactive labels and tab titles, not Body weight.

## Shape scale

M3's canonical scale, as M3 states it:

| M3 name | Corner radius | Use |
|---|---|---|
| Extra-small | 4px | Chips, badges |
| Small | 8px | Inputs |
| Medium | 12px | Buttons |
| Large | 16px | Cards, dialogs |
| Extra-large | 28px | Bottom sheets |
| Full | 9999px | Pills, avatars |

**This app's radii are in `DESIGN.md` and at least one step diverges on purpose.** Read them there.

And do not apply the table as a flat mapping: M3's per-component radii assume components sitting on a
surface, not nested inside one another. Nesting is concentric, inner equals outer minus padding, and
repeating one radius down the layers is the tell that no one did the subtraction.

## Component rules

- One filled button per action group (the primary action). Secondary actions use tonal, outlined,
  or text variants. Never two filled buttons side by side.
- Cards: `surface-container` background, `rounded-lg`, no shadow unless floating. Cards are
  not navigation targets by themselves; wrap in a `GestureDetector` for interactivity.
- FAB or prominent action button: persists during scroll for the single most important action.
  Not for destructive or rare actions.

## Motion

M3 uses spring-physics on Android/Compose. In Flutter, the closest equivalent is a
`CurvedAnimation` with `Curves.easeOutCubic` (entering) or `Curves.easeInCubic` (exiting). See
[motion-interaction.md](motion-interaction.md) for durations, reduced-motion patterns, and the table
of which motion tokens wind actually parses.

M3 easing reference (use as curve approximations in Flutter `AnimationController`):

- Entering: `emphasized-decelerate` ~ `cubic-bezier(0.05, 0.7, 0.1, 1)` -> `Curves.easeOutCubic`
- Exiting: `emphasized-accelerate` ~ `cubic-bezier(0.3, 0, 0.8, 0.15)` -> `Curves.easeInCubic`
- Standard: `cubic-bezier(0.2, 0, 0, 1)` -> `Curves.easeInOutCubic`

## Accessibility

- Touch targets: minimum 48x48dp (Material spec); WCAG 2.5.8's floor is 24px and Apple asks 44.
  WHICH technique reaches the target depends on the control, and the obvious one is measurably wrong
  on a button here; `.claude/rules/design.md` names the right one per control.
- The role system guarantees >=3:1 on `on-*` pairings for large text. Body text still needs 4.5:1.
  See [accessibility-wcag.md](accessibility-wcag.md) for what enforces it here.
- Components must ship a visible focus ring. Wind's focus state is the `focus:` prefix; there is no
  `focus-visible:`, and an unknown prefix drops the whole class silently, so a ring written that way
  never renders. `FocusableActionDetector` is the Flutter-side route.
- Provide `Semantics` for non-text content. Never use color alone, and that applies to selection
  state as much as to status.

## How to apply in this codebase

1. Use semantic tokens exclusively: never raw hex, never `Colors.*` constants in className.
2. Express depth by stepping `bg-surface` -> `bg-surface-container` -> `bg-surface-container-high`,
   not by adding shadows, and read the direction off `DESIGN.md` rather than assuming it.
3. Take the type step from `DESIGN.md`; weight 500-600 for interactive labels.
4. Take the radius from `DESIGN.md`, then subtract the padding for anything nested.
5. For Material widget sub-trees (if used), the generated `ThemeData` from `design:sync` wires
   the `ColorScheme` automatically. Do not override `ThemeData.colorScheme` by hand.

## See also

- [DESIGN.md](../DESIGN.md): this app's own token values, type scale, radii and where they diverge
- [.claude/rules/design.md](../../.claude/rules/design.md): how they are applied, and the measured anti-patterns
- [wind-responsive.md](wind-responsive.md): breakpoints and navigation layout patterns
- [accessibility-wcag.md](accessibility-wcag.md): contrast requirements and design:lint enforcement
- [refactoring-ui.md](refactoring-ui.md): craft: hierarchy, spacing, type, color, and depth polish
- [motion-interaction.md](motion-interaction.md): easing, duration, and reduced-motion in Flutter

## Sources

- m3.material.io: color/roles, styles/typography, styles/shape, styles/motion/easing-and-duration,
  components, foundations/accessible-design.
- Flutter documentation: ColorScheme.fromSeed, ThemeData, AnimationController, CurvedAnimation.
- material-foundation/material-color-utilities (HCT, tonal palette generation).
