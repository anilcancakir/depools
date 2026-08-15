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
- Content width caps at `max-w-6xl` (1152px), centred. Set once as `MagicStarter.manager.pageContainerClassName` in `AppServiceProvider.boot`, never per page. The cap is generous rather than a reading column, but it is a cap: an uncapped product row on a desktop window puts the quantity an eye-movement away from the name it belongs to.
- Every page goes through `MSPageScaffold`. It owns the surface fill, the scroll, the shared geometry and the header, so a page never hand-rolls its own chrome. A page that does drifts from its neighbours in width and header offset inside the same shell.
- Reflow vertically at narrow widths. **Never truncate a control, a badge row or a number to fit.** A NAME in a list row may ellipsise, and that exception is deliberate: wrapping a 40-character product name to three lines makes a grouped list unscannable, and the full name is one tap away on the detail screen. Everything else reflows. `LotRow` is the worked example of both halves at once, its meta row wrapping while its product name truncates, and the reason is in that recipe's own comment.
- **One app, one feature set, one design.** iOS, Android and web run the same Flutter source, and every feature is present on all three. Layout adapts to WIDTH, never to platform: `md:` and `lg:` prefixes are the tool, `ios:`/`web:` prefixes are not. There is no web-only screen and no mobile-only screen, and a control is never hidden because of the platform it is running on.
- Where the hardware genuinely differs, the app uses what the platform offers instead of dropping the feature. A receipt photo is the camera on a phone, and the camera or a file picker on desktop; the screen, the parse, the review and the result are identical.
- Never branch the widget tree per platform when a breakpoint prefix expresses the same thing. (The reflow rule above used to be repeated here in full, with a slightly different wording, which is how the truncation exception came to be missing from one copy and not the other.)

### A screen operated with the keyboard open budgets for the keyboard

**On a phone the keyboard is a third of the screen, and a screen whose work happens WHILE typing has to be laid out against what is left, not against the full height.** The count screen was drawn against 844 and measured like this at 390x844:

| band | height |
|---|---|
| location chip wall | 235 |
| search field | 48 |
| settled bar | 81 |
| count list, the actual work | **66** |

The list began at y=621. So **any keyboard taller than 223px pushed every row off screen**, and every phone keyboard is far above that. Searching a shelf while looking at it was not slow, it was impossible, and nothing in a desktop browser can show this: Flutter web reports `viewInsets.bottom` as 0, so the layout looks fine in the only place the E2E driver can reach.

Three rules come out of it, and the first two are Apple's rather than ours.

**Search goes at the bottom when the screen is operated through it.** The HIG (search fields, June 2026) is explicit: "Place search at the bottom if there's room... it keeps the search experience easy to reach", and when tapped it "animates into a search field above the keyboard so they can begin typing". Settings, Mail and Notes ship it. Search stays at the top only when covering the bottom would interfere with the screen's primary function, which is the Wallet case.

**It can share that bar with the screen's primary action.** The HIG names both arrangements, its own toolbar (Settings) or alongside other controls (Mail, Notes). Prefer the second where a screen has one primary action, so the bar carries exactly one live action at all times rather than trading one out-of-reach control for another.

**Material 3's "docked search bar" is NOT this**, and reading it as support for bottom placement is a mistake worth naming once. M3 says a search bar is "typically placed at the top of a screen", and its docked-versus-full-screen split is about BREAKPOINT: a bounded results panel at medium and expanded widths against full-screen at compact. It says nothing about the bottom edge on a phone.

**Anything a screen exists for gets counted against the keyboard band, not the viewport.** Chrome above the work is the budget: on the count screen, collapsing a 235px picker to a 43px row and moving the field into the pinned bar took the list's start from 621 to 255, which is the difference between one visible row while typing and none. A pinned bar is anchored to the larger of its navigation clearance and the keyboard inset, never to their sum, since the keyboard covers the navigation while it is up.

## What to avoid

- Elevation shadows standing in for hierarchy.
- A flat radius on every nested layer.
- `bg-primary` on more than the one primary action in a view. Everything else is neutral.
- A warm grey ramp. This palette is deliberately cool and blue-cast; mixing in a stone or zinc grey makes it read as a different product.
- Purple or violet gradients on AI surfaces.
- Raw hex inside a component. Semantic tokens only, enforced by `.design-token-allowlist` and `bin/design-tokens`.
- **`text-accent`. It does not exist.** `accent` is declared here but `design:sync` emits only `bg-accent`, so `text-accent` drops silently and the text renders at full foreground brightness, which looks like a value rather than a hint. For tinted text use a status family: `text-ai` (teal) for anything the app inferred or suggested, `text-expiring` / `text-low-stock` for the states they name. `bin/design-tokens` cannot catch this, because a dropped alias is not a raw hex.
- **`border-bg-primary` and any other `border-<bg-token>` this file does not declare.** The alias expander matches a WHOLE token against a key, so `border-bg-primary` finds nothing, the border parser then sees an unknown colour, and the border vanishes with no warning. It looks valid because `magic_starter`'s input recipe uses `border-bg-destructive`; that only works where the theme declares that key. Same class of silent drop as `text-accent`.
- Borrowing a status family for something it does not name. An inference hint in `text-expiring` reads as a date warning; suggestions belong to `text-ai`, which is what DESIGN.md defines that family for.

## Overlay strokes: the pair that does not depend on the photograph

Two surfaces draw UI on top of an uncontrolled background: the barcode viewfinder's framing
rectangle and the shelf photo's region boxes. Both used `border-color-border`, a deliberately
low-contrast hairline that disappears over a white shelf label or a bright camera frame, and
neither can borrow `bg-primary`, because a `bg-` alias cannot be reused as a border colour
(`border-bg-primary` drops silently, see the avoid list above).

This was deferred for a while, and the reason was sound for what it was considering: picking one
hex against a placeholder rather than a real photograph is guessing at the thing that matters,
because the right value depends on the image.

**A single stroke cannot escape that. A pair can, and the escape is arithmetic rather than taste.**
For a background of relative luminance L, contrast to a light stroke is `1.05 / (L + 0.05)` and
contrast to a dark stroke is `(L + 0.05) / 0.05`. The two move in opposite directions, so the
better of the two is worst exactly where they cross, and nowhere else. With ideal black and white
that crossing is 4.58:1. With the values below it is **3.91:1**, at L = 0.191, and that figure is
the floor for every background that can ever exist behind them.

| Token | Value (both appearances) | Role |
|---|---|---|
| `border-color-overlay-ink` | `#1C1C1E` | outer stroke |
| `border-color-overlay-paper` | `#F2F2F7` | inner stroke |

Drawn as two concentric strokes, ink outside and paper inside. The darker stroke meets the
photograph at the hard outer boundary, which is what an edge over an image is expected to look
like, and the lighter one carries the shape when the image behind it is dark.

Both hold the same value on each side of `dark:`, like `depools_paper_tokens.dart`, because an
overlay's background is a photograph rather than a surface the app controls: it does not get
lighter because the user turned dark mode on.

**Not pure black and white**, which would buy 0.67 of a contrast point and read as a rendering
artefact rather than as part of the interface, the same way this file rejects pure black text on a
saturated fill. These are Apple's darkest and lightest system greys, and they are 15.25:1 against
each other, so the boundary between the two strokes is never the weak link.

`bin/verify-design-contrast.py` sweeps the whole luminance range and fails the build below 3:1,
rather than trusting the arithmetic in this section.

## Location hues: seven, because eight could not be told apart

A location carries a hue the user picks from a swatch (D119), so unlike every other colour in this
file it identifies rather than means. It lives in `lib/config/depools_location_tokens.dart` as a
further supplement, two tokens per hue holding the same value: `text-<hue>-location` for the glyph
in the tree, `bg-<hue>-location` for the same tone as the form's swatch fill.

| Hue | Glyph light | Glyph dark | Apple source |
|---|---|---|---|
| `slate` | `#5A5A5E` | `#AEAEB2` | systemGray |
| `blue` | `#0040DD` | `#409CFF` | systemBlue |
| `teal` | `#00697C` | `#5DE6FF` | systemTeal |
| `green` | `#1F7434` | `#30DB5B` | systemGreen |
| `amber` | `#8A3E00` | `#FFD426` | systemYellow |
| `red` | `#D70015` | `#FF6961` | systemRed |
| `violet` | `#3D0099` | `#DA8FFF` | systemPurple |

**Several hold the same hex as a status family, and that is agreement rather than reuse.** Both
vocabularies are built from Apple's increased-contrast values and neither reads the other. It is safe
because of this file's own rule, read in the direction that is easy to miss: colour never carries
meaning alone here, so `expired` always arrives as a filled badge with an icon AND the word, and a red
shelf glyph therefore cannot be misread as a date warning.

**`orange` was in this table and was removed by measurement.** Contrast is the wrong instrument for a
swatch: it compares a hue to the BACKGROUND, and a picker asks the user to tell hues apart from EACH
OTHER. Every one of the original eight cleared its contrast rows while amber and orange were the same
brown on screen in light mode, because Apple's increased-contrast yellow, orange and red all darken
toward brown and orange sat between the other two.

| Pair | CIEDE2000 | On screen |
|---|---|---|
| amber vs orange, light | 9.2 | the same colour |
| orange vs red, light | 10.1 | the same colour |
| amber vs orange, dark | 13.3 | clearly a yellow beside an orange |

So the floor is 12, calibrated between the two readings rather than chosen, and
`bin/verify-design-contrast.py` measures every pair in both appearances. Orange was dropped rather
than retuned, because retuning means inventing a value and every hue here is Apple's own. The
tightest surviving pair is `blue` against `violet` in light, at 15.1.

**The tree tints the GLYPH; it does not fill a chip behind it.** A 32px chip reads better in
isolation, and at the schema's maximum depth it would sit behind 60px of indent: 92px of gutter
before the name on a 390px phone.

**The form's swatch is the solid tone, not a soft tint of it**, so what the user taps predicts the
row they get. A soft pair was written first and removed: it made the swatch a pale version of a
glyph that renders at full strength two screens away. The tick on the chosen swatch is
`text-on-primary` rather than a per-hue foreground, because these fills follow the primary's own
brightness rule (dark in light mode, bright in dark) so one alias that flips with the appearance
lands on all seven. That is measured rather than asserted: the tightest is `red` at 5.38:1 in light
and `blue` at 6.51:1 in dark.

## The control edge is its own token

`MSSwitch` off renders a `#E7E6EC` track with a white thumb. On this palette's white card the
control's own edge measured **1.21:1**, and the `border` hairline only took it to 1.67:1. WCAG 1.4.11
asks 3:1 of a UI component's boundary and a switch cannot fall back on anything else: W3C's own
Understanding text exempts a control that has "visible content (such as text or a sufficiently
contrasting icon)", which is why `MSButton`'s secondary fill at 1.31:1 is fine and a switch is not.
Its track and thumb ARE the whole control.

Dark mode hid this completely, which is why it survived three screens until a light-mode pass.

So `border-color-control` exists, and it is deliberately heavier than the card hairline, because a
card edge and a control edge are two different jobs that this palette was doing with one token:

| | Value | vs `surface-container` | vs `surface` |
|---|---|---|---|
| light | `#8E8E93` | 3.26:1 | 2.92:1 |
| dark | `#7C7C80` | 4.09:1 | 5.05:1 |

Apple's increased-contrast `systemGray`, so the "every value here is Apple's own" property holds.

**The page-surface column falls short in light, at 2.92:1, and that is accepted with a reason.**
Every switch in this app sits on a card; a bare toggle on the page surface is not a pattern the
design uses. `bin/verify-design-contrast.py` prints that row as a note rather than dropping it, so
if a switch ever does land on the page the number is on screen instead of being rediscovered by eye.

**It is a hand-authored supplement, not a frontmatter token.** `design:sync` emits a FIXED table of
17 aliases and silently drops anything else: adding `border-strong` to the frontmatter produced no
alias at all, only a `design:lint` warning that it was unused. Same silent drop this file already
records for `text-accent`. Extending that table is a change to `magic`'s own command, so the token
lives in `lib/config/depools_control_tokens.dart` and is merged in `main.dart` alongside the status,
paper and overlay supplements.

## Verifying a change

1. Edit this file.
2. `python3 bin/verify-design-contrast.py` checks every pair here plus the status family. It works today, before the fork, and it covers more pairs than `design:lint` will: that one only checks `on-X`/`X`, this also checks text on every surface and every accent used as text.
3. `dart run bin/dispatcher.dart design:sync` regenerates `lib/config/wind_theme.g.dart`. Never hand-edit that file.
4. `dart run bin/dispatcher.dart design:lint` for the build-gate subset.
5. `bin/design-tokens` fails the build on a hardcoded colour outside the allowlist.
6. `docs/design-preview/index.html` recomputes every ratio live and renders the real screen, which is faster than a build cycle for judging a colour.

Current state: all 15 non-exempt pairs and all 7 status colours pass in both appearances, with the tightest margin at `accent / surface-container` in dark mode (4.94:1 against 4.5:1). Darkening `accent` dark below `#7D7AFF` is what would break first.

See also `docs/design-culture/apple-hig.md`, `accessibility-wcag.md` and `refactoring-ui.md`.
