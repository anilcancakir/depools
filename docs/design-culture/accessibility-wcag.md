# Accessibility / WCAG (Flutter/Wind reference)

Read this for every screen. Accessibility is a constraint that applies regardless of design
language, and it is legally required in most markets. Target WCAG 2.2 Level AA.

> **The success criteria here are WCAG's and are quoted as such. The token values are not.** What
> this app's colours measure, and which pairs are deliberately exempt with a recorded reason, is in
> `DESIGN.md` and in `bin/verify-design-contrast.py`. Component names are in
> `docs/component-registry.md`.

## What to target

WCAG 2.2 AA is the baseline (EN 301 549 / EU Accessibility Act, ADA Title II). WCAG 3.0 is a
draft; do not design to APCA for compliance yet.

## Contrast (hard numbers)

- Body text: **4.5:1** against its background.
- Large text (>=24px, or >=18.66px bold): **3:1**.
- UI components and meaningful graphics (borders, icons, input outlines, focus rings): **3:1**
  against adjacent color.
- Check BOTH light and dark independently; a token that passes in light can fail in dark.

### What enforces it here

Two tools, and the second covers more than the first.

`dart run bin/dispatcher.dart design:lint` checks 4.5:1 on the `on-X`/`X` role pairs declared in
`DESIGN.md`, implementing the WCAG relative-luminance formula against both the light and dark hex.
That is the build-gate subset.

`python3 bin/verify-design-contrast.py` is this app's own and checks more: text on every surface,
every accent used as text, the status vocabulary, ink against paper, the overlay stroke pair swept
across the whole luminance range, and the control edge. It also carries the EXEMPTIONS, each with the
reason attached, so a deliberately low-contrast token is a recorded decision rather than something to
rediscover: WCAG 1.4.3 and 1.4.11 both exclude inactive components, and a disabled control that met
4.5:1 would not read as disabled.

After any colour change in `DESIGN.md`: `design:sync`, then both checks.

Do not quote a ratio from memory. Every figure in this repository that was written from memory rather
than from the script's output has been wrong at least once.

## Touch targets

- WCAG 2.5.8 (AA): interactive targets at least **24x24 logical px**, or enough spacing so a
  24px circle on each does not overlap a neighbor.
- Apple HIG and Material 3 ask for 44px and 48px respectively; those are the practical targets.
- `min-h-11` is 44px and is correct on a plain `WDiv`. It is NOT correct on every control: on a
  `magic_starter` button it grows the box without re-centring the label, measured 4 logical px off, so
  padding is the technique there. `.claude/rules/design.md` names the right one per control and shows
  the arithmetic, including the case where the obvious padding value lands at 40 and quietly misses.

## Focus visibility

- WCAG 2.4.11 (AA): a focused element must not be fully hidden by sticky headers or overlays.
  In Flutter: use `Scrollable.ensureVisible` or `ScrollController` to scroll focused elements
  into view when a sticky header is present.
- Focus ring: at least 2px perimeter with 3:1 contrast against the unfocused state.
- **Wind's focus state is the `focus:` prefix. There is no `focus-visible:`.** An unknown prefix does
  not degrade, it drops the whole class (`wind_parser.dart` sets the class inactive and moves on), so a
  ring written as `focus-visible:ring-2` never renders and nothing reports it. `ring-*` and
  `ring-offset-*` themselves are supported; the prefix is what is not.
- Never use a Flutter `FocusNode` that suppresses the default focus indicator without a
  visible replacement.

## Flutter Semantics

Flutter does not use HTML; screen readers (TalkBack, VoiceOver) read the Semantics tree. Every
rule below maps the HTML/ARIA concept to Flutter.

### Every interactive widget needs a Semantics label

```dart
// Icon-only button
Semantics(
  label: 'Close dialog',
  button: true,
  child: WButton(onPressed: onClose, child: Icon(Icons.close)),
)

// Image with meaning
Semantics(
  label: 'Profile photo for Jane Smith',
  image: true,
  child: CircleAvatar(backgroundImage: ...),
)

// Decorative image: excludeSemantics: true
ExcludeSemantics(child: decorativeIcon)
```

### Heading hierarchy

Use `Semantics(header: true)` on screen-level headings. Maintain one primary heading per screen.
Do not use heading markup for visual sizing: the type scale carries the size, `Semantics(header: true)`
carries the role.

```dart
Semantics(
  header: true,
  child: WText('Profile settings', className: 'text-2xl font-semibold text-fg'),
)
```

### Form fields

Every input must have a visible, persistent label, and placeholder text is not a label because it
disappears on focus. `magic_starter`'s form field components handle the label and error association;
take the component from `docs/component-registry.md`.

Error messages must be text, not colour alone, and must be associated with the field rather than
floating near it.

**Do not tell the user to tap.** The affordance carries the action and the label carries the state; a
label reading "tap to fix" explains a touchscreen. `semanticLabel` is the exception, because a screen
reader has no affordance to feel, and that is where an instruction belongs if one is genuinely needed.

### Live regions for dynamic updates

Toast notifications and async status updates must announce themselves to screen readers:

```dart
Semantics(
  liveRegion: true,
  child: WText('Profile saved successfully.', className: 'text-sm text-fg'),
)
```

For urgent alerts use `Semantics(liveRegion: true, namesRoute: false)` with a high-priority
announcement. Do not use live regions for every state change; only for content the user would
otherwise miss.

### Navigation landmarks

Wrap the main content area in `Semantics(explicitChildNodes: true)` to preserve tree structure.
The `AppLayout` shell handles landmark-level semantics; do not add redundant wrappers.

## Color independence

Never convey information by color alone (WCAG 1.4.1). Pair every color signal with text, an
icon, or a pattern:

- An error input field gets an error tone AND an error message AND an error icon.
- A status badge has its tone AND an icon AND a label. This is what keeps two adjacent statuses
  distinguishable when their tones sit close together, which happens more often than it sounds.
- An active nav item gets its tone AND weight AND an indicator.
- **Selection is a state and this applies to it too.** A row distinguished from its neighbours by a
  fill tint alone is a subtle difference in light mode and no difference at all to a colour-blind
  user; add a radio dot, a tick or a glyph.

## Reduced motion

Respect the OS "Reduce Motion" setting, **in Dart**:

```dart
// In a widget build method
final reduceMotion = MediaQuery.of(context).disableAnimations;

controller.duration = reduceMotion ? Duration.zero : const Duration(milliseconds: 200);
```

There is no `motion-safe:` prefix in wind, and an unknown prefix drops the whole class, so a
className that appears to gate an animation gates nothing. See
[motion-interaction.md](motion-interaction.md) for which motion tokens wind actually parses.

Under reduced motion: disable parallax, large translates/scales, looping autoplay, staggered
reveals, and spinner animations. Keep or substitute: opacity fades, color transitions. Do not
delete motion that conveys state; substitute a static equivalent.

No content flashes more than 3 times per second. Auto-playing motion over 5 seconds needs a
pause control.

## Dragging and gestures

Every drag interaction (sortable lists, sliders, swipe-to-dismiss) needs a single-pointer
non-drag alternative (WCAG 2.5.7 AA). For swipe-to-dismiss: also show a button or
long-press-menu option to trigger the same action.

## Design-time checklist

Before marking any screen done:

1. Text contrast >=4.5:1 (3:1 large), verified in both light and dark by the two tools above, not by
   eye and not from memory.
2. UI component boundary contrast >=3:1 — **but check for text or an icon first.** W3C's Understanding
   of 1.4.11 is explicit: a control with visible content that identifies it needs no boundary
   indication. So a labelled button's low-contrast fill is not a failure, and a switch is the opposite
   case and does fail, because its track and thumb ARE the whole control.
3. No colour-only signals: every state has a text or icon companion.
4. Touch targets >=44px, reached by the technique that is correct for that control.
5. Visible focus ring on every interactive widget, using the `focus:` prefix, never obscured by
   sticky chrome.
6. One primary screen heading with `Semantics(header: true)`.
7. Every input has a visible label; errors are text and associated with the field.
8. Decorative images have `ExcludeSemantics`; informative images have a `Semantics(label: ...)`.
9. All interactive elements keyboard/switch-accessible; no widget swallows focus without release.
10. Non-essential motion gated behind `!MediaQuery.of(context).disableAnimations` in Dart.

## How to apply in this codebase

- The role pairs are designed to pass; a custom pair is not, so re-check it. Run
  `dart run bin/dispatcher.dart design:lint` and `python3 bin/verify-design-contrast.py` after every
  colour change in `DESIGN.md`.
- A control whose SHAPE is carried by a fill needs an explicit edge, and the card hairline is not
  strong enough for it: `.claude/rules/design.md` names the token that is and records what each
  measured.
- `magic_starter`'s form components handle label association and error text; take the component from
  `docs/component-registry.md` rather than building one.
- `WButton`, `WInput` and `WAnchor` ship with a focus-ring className. Keep it; never strip it.
- Use `ExcludeSemantics` for decorative icons; `Semantics(label: ...)` for meaningful ones.
- A screen is not verified until it has been seen in light AND dark. Both appearances, every time:
  this was skipped for seven consecutive screens once and the light-mode defect had already shipped
  across six of them.

## See also

- [DESIGN.md](../DESIGN.md): color values; run design:lint to verify pairs
- [refactoring-ui.md](refactoring-ui.md): color independence, hierarchy, empty states
- [motion-interaction.md](motion-interaction.md): reduced-motion patterns
- [wind-responsive.md](wind-responsive.md): touch targets, SafeArea, hit-target sizing

## Sources

- W3C WAI: WCAG 2.2 Recommendation (1.4.1, 1.4.3, 1.4.11, 2.1.1, 2.4.3, 2.4.7, 2.4.11, 2.5.7,
  2.5.8, 3.3.1-3.3.3).
- Flutter documentation: Semantics, ExcludeSemantics, MediaQuery.disableAnimations,
  FocusableActionDetector.
- EN 301 549 / EU Accessibility Act; ADA Title II.
