# Apple Human Interface Guidelines (Flutter/Wind reference)

Read this before building a screen that should feel native on Apple platforms. It is a decision tool:
pick the language, then apply the rules. The guidance below is adapted from HIG principles to
Flutter/Wind/Magic idioms.

> **This file names roles, never values.** It states what HIG asks for; it does not state what this
> app's tokens, components or breakpoints are. For a hex, a radius, a type size or a component name,
> `DESIGN.md` and `docs/component-registry.md` are the authority, and `.claude/rules/design.md`
> carries how they are applied here. Every value this file used to quote was the starter's and had
> gone stale.

## When to choose this language

Choose Apple HIG when:

- The audience is Apple-ecosystem-native and expects iOS/iPadOS patterns (bottom tab bar, swipe-back, edge gestures).
- The product is content-first: chrome should recede so content leads.
- Calm, restrained minimalism fits the brand better than loud expression.

Avoid it when:

- The product must reach Android parity equally (use material-design-3 instead).
- The domain is data-dense or tool-heavy; Material's explicit density fits better.
- The brand needs expressive, decorative visuals.

## Core principles

- **Clarity**: legible text at every size, precise icons, subtle adornment.
- **Deference**: the UI helps users interact with content without competing with it.
- **Depth**: layers communicate hierarchy via tonal elevation, not heavy drop shadows.

## Layout and spacing rules

- Every interactive element needs a minimum 44x44 logical-px hit target. Pad invisibly rather than
  shrink the control. HOW to reach 44 depends on the control: `.claude/rules/design.md` records
  which technique is correct for which one here, and measured that the obvious one is off centre on
  a button.
- Use generous whitespace. Wind spacing follows the 4px logical scale; prefer `p-4`/`p-6`/`gap-4`
  and resist `p-2` on content areas.
- Screen-edge margins widen with the viewport rather than staying constant. Do not reuse one margin
  across all breakpoints; `DESIGN.md`'s Layout section carries this app's pair.
- Reflow vertically at narrow widths rather than truncate.
- Derive nested corner radii concentrically: **inner radius = outer radius minus padding.** The
  arithmetic is subtraction, so a card whose padding equals its own radius gets a much smaller inner
  radius, not the next step down. `DESIGN.md` works an example on this app's own scale. A flat
  radius repeated on every layer is the generic-app tell.

See [wind-responsive.md](wind-responsive.md) for the breakpoint map and which prefix the shell
actually switches on.

## Typography

- Let type carry hierarchy: bolder, left-aligned section headings. **Keep one font family.**
  `DESIGN.md` decides which, and whether a second family earns an exception for a specific job.
- Use the type scale rather than arbitrary sizes. The scale, its steps and their names live in
  `DESIGN.md`; do not invent a size at the call site.
- Body weight 400, headings and interactive labels weight 600-700. Never below 400 for small text.
- Left-align body text; never center multi-line prose.

## Color and material

- Use semantic tokens only. Never raw hex inside a component.
  - Page canvas: `bg-surface`
  - Cards and sheets: `bg-surface-container`
  - Primary action: `bg-primary text-on-primary`
  - Destructive: `bg-destructive text-on-destructive`
  - Body text: `text-fg`
  - Secondary text: `text-fg-muted`
  - Hairlines: `border-color-border`

  Those are ROLE names. Each alias already expands to a light and dark pair, so write the alias on
  its own and never add a `dark:` beside it. The hex behind each role, and the token families this
  app adds beyond the canonical set, are in `DESIGN.md`.

- Tint, do not repaint: apply `bg-primary` to primary actions only, one per view. Keep chrome
  neutral (`bg-surface-container`, `text-fg`).
- In dark mode, elevation goes lighter: `surface-container` sits above `surface`. **The direction
  inverts between appearances**, which is why no fill token can mean "pressable" in both and a
  border has to carry it; `.claude/rules/design.md` records the measurement. Whether this app's
  darkest surface is pure black or an elevated grey is `DESIGN.md`'s call, not HIG's, and it has
  reasons either way.
- Reserve translucency for the navigation layer only, and only if the design uses it at all. A
  palette built on tonal surfaces does not need glass, and `DESIGN.md` says whether this one wants
  it. Never glass-on-glass, never glass in the content layer.

## Motion (Apple-specific feel)

See [motion-interaction.md](motion-interaction.md) for Flutter easing/duration mechanics.

Apple-specific feel:

- Transitions originate from the element that triggered them (a sheet slides up from the
  triggering button's area, not from a random edge).
- Use spring-based or ease-out curves; keep micro-interactions under 300ms.
- Animate state transitions that communicate hierarchy, not frequent interactions.
- Guard non-essential animation behind `MediaQuery.of(context).disableAnimations`. Do this in Dart:
  wind has no `motion-safe:` prefix, and an unknown prefix drops the whole class silently
  (`wind_parser.dart`), so a className that looks like it respects Reduce Motion does nothing at all.

## Accessibility

- Contrast: 4.5:1 for normal text, 3:1 for large text and UI components, in BOTH light and dark.
  `design:lint` checks the `on-X`/`X` role pairs; this app additionally runs
  `bin/verify-design-contrast.py`, which covers text on every surface and every accent used as
  text. See [accessibility-wcag.md](accessibility-wcag.md).
- Support text scaling: never hardcode font sizes for primary content. Flutter's text scale respects
  the OS setting as long as sizes come from the scale rather than from a literal.
- Respect Reduce Motion: substitute a crossfade or opacity fade, do not delete animations.
  Use `MediaQuery.of(context).disableAnimations` in Dart.
- Never use color as the only signal. Pair every color-only state with an icon or text label.
- Provide `Semantics` labels on icon-only controls:
  ```dart
  Semantics(label: 'Close', child: WButton(onPressed: ..., child: Icon(Icons.close)))
  ```

## What makes it feel authentically Apple

Reproduce: restraint (one primary surface per view), generous whitespace, crisp single-family
type, semantic adaptive color, subtle depth via tonal elevation. Avoid the tells of a cheap
imitation: raw hex, fixed text sizes, multiple typefaces, red used for non-destructive actions,
dense cramped layouts.

## How to apply in this codebase

1. Take the type scale from `DESIGN.md` and the component from `docs/component-registry.md`. Do not
   invent either at the call site.
2. Use semantic tokens exclusively in wind `className`: `bg-surface text-fg`,
   `bg-primary text-on-primary`, `border-color-border`.
3. Dark mode is not optional: each token carries its `dark:` pair, and a screen is not verified
   until it has been seen in BOTH. The two appearances are not brightness variants of each other.
4. Honor 44px targets, using the technique `.claude/rules/design.md` names for that control.
5. Keep radii concentric: subtract the padding from the outer radius. Do not repeat one radius down
   the layers.
6. Reserve `bg-destructive` for genuinely destructive actions, matching Apple's reserved-red rule.

## See also

- [DESIGN.md](../DESIGN.md): this app's own token values, type scale, radii and material rules
- [.claude/rules/design.md](../../.claude/rules/design.md): how they are applied, and the measured anti-patterns
- [wind-responsive.md](wind-responsive.md): breakpoints, safe-area, sidebar vs bottom nav
- [accessibility-wcag.md](accessibility-wcag.md): contrast requirements and what enforces them
- [motion-interaction.md](motion-interaction.md): easing, duration, and reduced-motion patterns in Flutter
- [material-design-3.md](material-design-3.md): M3 alternative when Material feel is preferred

## Sources

- Apple HIG: Design Principles, Layout, Typography, Color, Motion, Accessibility
  (developer.apple.com/design/human-interface-guidelines).
- Flutter documentation: Semantics, MediaQuery.disableAnimations, TextScaleFactor.
