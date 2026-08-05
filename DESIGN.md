---
name: Depools
description: >
  AI-assisted inventory for small businesses and households. Apple-first restraint:
  Apple's own increased-contrast system colours, a single Inter family with Geist Mono
  for quantities and codes, tonal surfaces instead of shadows, and one chromatic accent
  with everything else neutral.
colors:
  surface:
    light: "#F2F2F7"
    dark: "#000000"
  surface-container:
    light: "#FFFFFF"
    dark: "#1C1C1E"
  surface-container-high:
    light: "#E5E5EA"
    dark: "#2C2C2E"
  fg:
    light: "#000000"
    dark: "#FFFFFF"
  fg-muted:
    light: "#5A5A5E"
    dark: "#AEAEB2"
  fg-disabled:
    light: "#BCBCC0"
    dark: "#545456"
  primary:
    light: "#0040DD"
    dark: "#409CFF"
  on-primary:
    light: "#FFFFFF"
    dark: "#00142E"
  primary-container:
    light: "#E3ECFF"
    dark: "#002357"
  accent:
    light: "#3634A3"
    dark: "#7D7AFF"
  border:
    light: "#D1D1D6"
    dark: "#3A3A3C"
  border-subtle:
    light: "#E5E5EA"
    dark: "#2C2C2E"
  destructive:
    light: "#D70015"
    dark: "#FF6961"
  on-destructive:
    light: "#FFFFFF"
    dark: "#2A0004"
  destructive-container:
    light: "#FFE5E7"
    dark: "#40000A"
  success:
    light: "#1F7434"
    dark: "#30DB5B"
  warning:
    light: "#8A3E00"
    dark: "#FFB340"
typography:
  display:
    fontFamily: Inter
    fontSize: 34px
    fontWeight: "700"
    lineHeight: 41px
    letterSpacing: -0.02em
  headline-lg:
    fontFamily: Inter
    fontSize: 28px
    fontWeight: "700"
    lineHeight: 34px
    letterSpacing: -0.01em
  headline-md:
    fontFamily: Inter
    fontSize: 22px
    fontWeight: "600"
    lineHeight: 28px
  title-lg:
    fontFamily: Inter
    fontSize: 17px
    fontWeight: "600"
    lineHeight: 24px
  body-lg:
    fontFamily: Inter
    fontSize: 17px
    fontWeight: "400"
    lineHeight: 25px
  body-md:
    fontFamily: Inter
    fontSize: 15px
    fontWeight: "400"
    lineHeight: 22px
  label-md:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: "600"
    lineHeight: 20px
    letterSpacing: 0.01em
  label-sm:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: "500"
    lineHeight: 16px
  metric:
    fontFamily: Geist Mono
    fontSize: 15px
    fontWeight: "500"
    lineHeight: 22px
rounded:
  sm: 4px
  DEFAULT: 8px
  md: 12px
  lg: 16px
  xl: 22px
  full: 9999px
spacing:
  xs: 4px
  sm: 8px
  md: 16px
  lg: 24px
  xl: 40px
  2xl: 64px
  gutter: 16px
  section: 32px
components:
  button-primary:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.on-primary}"
    rounded: "{rounded.md}"
    padding: "{spacing.md}"
  button-destructive:
    backgroundColor: "{colors.destructive}"
    textColor: "{colors.on-destructive}"
    rounded: "{rounded.md}"
    padding: "{spacing.md}"
  card-surface:
    backgroundColor: "{colors.surface-container}"
    rounded: "{rounded.lg}"
    padding: "{spacing.lg}"
  input-surface:
    backgroundColor: "{colors.surface-container-high}"
    textColor: "{colors.fg}"
    rounded: "{rounded.md}"
    padding: "{spacing.sm}"
---

# Depools design concept

Apple-first, which in 2026 means restraint rather than flourish: tonal surfaces instead of elevation shadows, concentric corner radii, one chromatic accent and neutral everywhere else, and a cool blue-cast grey. The chosen palette is "System Native", built from Apple's own published system colours rather than an invented brand palette.

Selected from four candidates rendered as the real inventory screen in `docs/design-preview/`. That preview page still works and recomputes every contrast ratio live, so it is the place to test a change before editing this file.

## Colour: why the increased-contrast variants

Apple publishes each system colour in four forms: default light, default dark, increased-contrast light, increased-contrast dark. **We use the increased-contrast pair as our base**, not the default pair.

The reason is measured, not stylistic. Our surfaces are `#F2F2F7` and `#000000`, and `design:lint` enforces WCAG AA. Apple's default values do not clear it on those surfaces:

| Pair | Default | Increased contrast | Required |
|---|---|---|---|
| systemGreen on `#F2F2F7` | `#34C759` = 1.98:1 | `#248A3D` = 3.91:1 | 3:1 |
| white on systemBlue | `#007AFF` = 4.02:1 | `#0040DD` = 7.56:1 | 4.5:1 |

So the choice is not "Apple values or accessible values". Both columns are Apple's. We take the column that survives our own build gate, and nothing here is invented.

Two consequences worth knowing before editing a colour:

**Dark-mode accents carry dark text.** The increased-contrast dark variants are deliberately brighter so they separate from a black background, which means white text on them fails. `#409CFF` with white is 2.83:1; with near-black it is above 7:1. This is why `on-primary` is dark in dark mode. It reads as intentional, it is Apple's own logic, and it is not a mistake to be "fixed".

**These values are a snapshot, not a binding.** Apple's own guidance says to avoid hard-coding system colour values because they may change between releases. A Flutter app driving its own token system cannot call `UIColor`, so we hard-code by necessity. Re-check against the HIG when a major iOS version lands.

### Two greys and a near-black

`fg-muted` light is `#5A5A5E`, slightly darker than Apple's increased-contrast `systemGray` (`#6C6C70`), because secondary text at 15px needs 4.5:1 against `#F2F2F7` and `#6C6C70` lands just under.

`on-primary` and `on-destructive` in dark mode are near-blacks tinted toward their accent (`#00142E`, `#2A0004`) rather than pure `#000000`. Pure black on a saturated fill reads as a hole; a tinted near-black reads as part of the same material.

## Status colours

Depools has status meanings the canonical token set does not cover, so they live in a supplement file (`lib/config/depools_status_tokens.dart`) merged into the Wind alias map, following the same pattern `uptizm` uses for its monitoring vocabulary. `design:sync` does not read them from here.

Each status is a triple: `solid` for the dot or icon, `soft` for the badge background, `soft-foreground` for the badge text.

| Status | Solid light | Solid dark | Meaning |
|---|---|---|---|
| `in-stock` | `#1F7434` | `#30DB5B` | enough on hand |
| `low-stock` | `#8A3E00` | `#FFD426` | below par or reorder point |
| `out-of-stock` | `#5A5A5E` | `#AEAEB2` | none left |
| `expiring` | `#A82B00` | `#FFB340` | expires within the window |
| `expired` | `#D70015` | `#FF6961` | past its date |
| `wasted` | `#6B5439` | `#B59469` | discarded, spoiled, broken |
| `ai` | `#00697C` | `#5DE6FF` | AI-driven surface |

Derived from Apple's increased-contrast systemGreen, systemYellow, systemGray, systemOrange, systemRed, systemBrown and systemTeal, darkened further in light mode only where 4.5:1 as badge text required it.

Three rules on top:

**Colour never carries meaning alone.** Every status badge pairs its colour with an icon and a Turkish label. This is WCAG 1.4.1 and it is also the only thing that makes `low-stock` and `expiring` reliably distinguishable, because Apple's increased-contrast yellow and orange both resolve to brown-red tones in light mode and sit closer together than their default counterparts do.

**The AI accent is teal, deliberately not purple.** The violet-to-pink gradient is the strongest visual tell of an AI-generated interface, and it is a cliché worth stepping around. Teal is inside Apple's own palette, is cool and unambiguous, and does not collide with `primary` blue at badge size.

**`expired` equals `destructive`.** A product past its date and a dangerous action should read alike, the same way `uptizm` makes `down` equal `destructive`.

## Typography: one family

Inter for everything, Geist Mono for quantities, prices and barcodes. Not a display and body pairing.

Four candidate pairings were rendered side by side at the real type scale, and at UI sizes they were nearly indistinguishable, because all of them are neo-grotesques doing the same job. `docs/design-culture/apple-hig.md` already says to keep one font family, so two families would break that rule for no visible gain.

**The scale follows iOS rather than a generic web ladder.** Body is 17px, not 16px, because that is the iOS default and it is what makes an app feel native at a glance. `title-lg` and `body-lg` share 17px and differ only in weight, which is exactly how iOS distinguishes Headline from Body.

**Geist Mono earns its place on alignment, not looks.** A column of quantities has to line up: `1.240,00` above `18,50` above `111,11`. Every digit is fixed-width in a monospace by construction, so routing quantities through it sidesteps having to verify tabular numeral support per family. Inter does have tabular numerals, so `font-variant-numeric: tabular-nums` is available where mono would be too heavy.

**Turkish is a hard requirement and it is verified.** `ı` (U+0131) ships in the base latin subset, while `Ğ ğ İ Ş ş` live in `latin-ext` (U+0100-02BA). Both subsets must be requested. Loading only `latin` silently breaks Turkish text, and the failure looks like a font-fallback glitch rather than a missing glyph, so it is easy to miss.

## Material and depth

- **Tonal surfaces, not shadows.** Hierarchy comes from `surface` to `surface-container` to `surface-container-high`. Reserve `shadow-sm` for a floating element that genuinely floats, `shadow-md` for dropdowns, `shadow-lg` for modals. Never stack them, never put one on a card that is already distinguished by its fill.
- **Concentric corners.** Inner radius equals outer radius minus padding. A `rounded-lg` (16px) card with 16px padding gets `rounded-sm` (4px) on a nested control, not another 16px. Apple's own guidance calls non-concentric nesting a source of visual tension, and a flat 12px on every layer is the generic-app tell.
- **Fewer borders.** Separate with a surface-contrast shift or spacing before reaching for `border`. The hairline `border` token exists for card edges, and it is deliberately low contrast: WCAG 1.4.11 applies to UI components and meaningful graphics, not to a decorative separator whose boundary is already carried by the fill. Apple's own `separator` at 29% opacity would fail a 3:1 test too.

### Two tokens are deliberately low contrast

`fg-disabled` (1.89:1) and `border` (1.52:1) look like failures and are not. WCAG 1.4.3 and 1.4.11 both exclude inactive components, and a disabled control that met 4.5:1 would not read as disabled. Both are marked exempt in `bin/verify-design-contrast.py` with the reason attached, so the exemption is a recorded decision rather than something to rediscover.
- **`xl` radius is 22px**, not 20px, to sit closer to the capsule feel current iOS uses on large controls.

## Layout

- Minimum 44x44 hit target on everything interactive. Pad invisibly rather than shrink a control.
- Screen-edge margins: `p-4` (16px) on mobile, `md:px-5` (20px) at wider widths. Not one margin everywhere.
- Reflow vertically at narrow widths. Never truncate to fit.
- Mobile is the capture surface, web is the review surface. Design each for its job rather than making one a scaled copy of the other.

## What to avoid

- Elevation shadows standing in for hierarchy.
- A flat radius on every nested layer.
- `bg-primary` on more than the one primary action in a view. Everything else is neutral.
- A warm grey ramp. This palette is deliberately cool and blue-cast; mixing in a stone or zinc grey makes it read as a different product.
- Purple or violet gradients on AI surfaces.
- Raw hex inside a component. Semantic tokens only, enforced by `.design-token-allowlist` and `bin/design-tokens`.

## Verifying a change

1. Edit this file.
2. `python3 bin/verify-design-contrast.py` checks every pair here plus the status family. It works today, before the fork, and it covers more pairs than `design:lint` will: that one only checks `on-X`/`X`, this also checks text on every surface and every accent used as text.
3. `dart run bin/dispatcher.dart design:sync` regenerates `lib/config/wind_theme.g.dart`. Never hand-edit that file.
4. `dart run bin/dispatcher.dart design:lint` for the build-gate subset.
5. `bin/design-tokens` fails the build on a hardcoded colour outside the allowlist.
6. `docs/design-preview/index.html` recomputes every ratio live and renders the real screen, which is faster than a build cycle for judging a colour.

Current state: all 15 non-exempt pairs and all 7 status colours pass in both appearances, with the tightest margin at `accent / surface-container` in dark mode (4.94:1 against 4.5:1). Darkening `accent` dark below `#7D7AFF` is what would break first.

See also `docs/design-culture/apple-hig.md`, `accessibility-wcag.md` and `refactoring-ui.md`.
