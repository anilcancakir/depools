# Refactoring UI craft (Flutter/Wind reference)

Read this for every screen, regardless of design language. Apple/Material decide the visual
identity; this decides whether the result looks designed or amateur. These are defaults to apply,
not options to choose.

Source: "Refactoring UI" (Wathan and Schoger) adapted to Flutter/Wind/Magic idioms.

> **This file names craft, never values or components.** For a hex, a radius, a type step or a
> component name, `DESIGN.md`, `docs/component-registry.md` and `.claude/rules/design.md` are the
> authority. The examples below use role names and generic widgets on purpose.

## Hierarchy (the highest-leverage skill)

Not all elements are equal. Give every screen one clear primary action; demote the rest. Build a
pyramid: one primary, a few secondary, the rest tertiary.

Emphasize by de-emphasizing. To make the primary stand out, soften the secondary; do not just
enlarge the primary.

Use the levers in this order: color/contrast first, font-weight second, size last. Size alone is
a weak signal.

- Cap variety: 2-3 font weights and 2-3 text-contrast levels per screen. More tiers read as noise.
- For secondary text use lower contrast, not smaller size. Use `text-fg-muted` rather than
  dropping the font size.
- For labels, prefer format and context over a label ("12 left in stock", not "Stock: 12").
- Style by visual role, not widget type. A heading can be small; a button text can be quiet.

### Applying hierarchy with Wind tokens

```dart
// Primary body text
WText('Your profile has been updated.', className: 'text-fg text-base')

// Secondary helper text
WText('Changes take effect immediately.', className: 'text-fg-muted text-sm')
```

For actions, the hierarchy is one filled primary per view, a quieter secondary, and a link-shaped
tertiary. The button component and its intent axis come from `docs/component-registry.md` and
`magic_starter`; reserve the destructive intent for genuinely destructive actions.

**Do not express "unavailable" by disabling a control and leaving it at that.** Measured in this
theme: a disabled button in the primary intent is visually indistinguishable from a live one, so a
disabled control invites a fight the user cannot win and gives no feedback when they try. Either
remove the control or put the blocking reason where it would have been.

## Anti-AI-slop tells

The following patterns are how generated or rushed UI gives itself away. Avoid all of them.

- **Purple-on-gray everything**: primary color leaked onto every surface. Reserve `bg-primary`
  for the one primary action per view. Everything else is neutral.
- **All text the same size and weight**: no hierarchy. Use the declared type steps, and vary weight
  before varying size.
- **Cards with too much padding and no content**: a card that is mostly whitespace with one short
  line of text. Cards need meaningful content density.
- **Every section the same vertical rhythm**: no breathing room variation between a dense form
  and a spacious hero. Use the spacing scale deliberately.
- **Placeholder content left in production**: "Lorem ipsum", "User Name", "Coming soon" states
  with no real data shape. Design with realistic data from the start.
- **No empty state designed**: lists and feeds without a "no data" state. Every list needs a
  designed empty state (icon + title + one clear CTA).
- **Icon-only buttons with no label and no Semantics**: inaccessible and confusing. Add a
  `Semantics(label: ...)` wrapper or a visible label.
- **Shadows on everything**: depth without meaning. Reserve `shadow-sm` for cards/inputs,
  `shadow-md` for dropdowns, `shadow-lg` for modals. Do not stack.
- **Flat gray on gray**: a form input indistinguishable from the surface it sits on. It needs its own
  tone or its own edge. WHICH depends on the palette and is not a free choice: measured here, the
  input tone on a white card is DARKER than the card, which is the universal look of a disabled
  control, so an enabled field on a card takes card tone plus a border instead. Elevation direction
  inverts between appearances, so check both. `.claude/rules/design.md` carries the measurement.

## Spacing and layout

- Start with too much whitespace, then remove. Under-spacing is the more common failure.
- Enforce the relationship rule: space INSIDE a group < space BETWEEN groups < space around a
  section. Proximity is how users perceive grouping.
- Use the Wind 4px logical scale only: `p-1`(4px) `p-2`(8px) `p-3`(12px) `p-4`(16px)
  `p-6`(24px) `p-8`(32px) `p-12`(48px) `p-16`(64px). If a value is not on the scale, snap to
  the nearest step; never invent an arbitrary offset.
- Do not fill available width. Constrain a text column with a `ConstrainedBox` (`max-w-prose` is the
  token equivalent). Page-level width is the shell's job and is set once, not per screen; see
  [wind-responsive.md](wind-responsive.md).
- Dense data UIs (tables, dashboards) use a compressed scale (drop one or two steps), not a
  different arbitrary set.

### Spacing in practice

```dart
// Section separation: gap-6 (24px) between sections
WDiv(
  className: 'flex flex-col gap-6 p-4',
  children: [
    SectionHeader(),
    FormContent(),    // gap between items inside: gap-4
    ActionRow(),
  ],
)

// Group separation: gap-4 (16px) between form fields
WDiv(
  className: 'flex flex-col gap-4',
  children: [nameField, emailField, passwordField],
)
```

## Typography

- Use the type scale from `DESIGN.md` rather than picking a `text-*` size at the call site.
- `DESIGN.md`'s font choice is authoritative. Do not add a typeface per component; if the design
  declares a second family for a specific job (a monospace for figures, say), use it only for that job.
- Weight: `font-normal` (400) for body, `font-medium` (500) for UI labels, `font-semibold` (600)
  for headings and primary actions. Never below 400 for body or small text.
- Line-height is inverse to size: body `leading-relaxed` (1.5-1.6), UI components `leading-tight`
  (1.2-1.3), headings `leading-snug` (1.1-1.2).
- Left-align body; never center multi-line prose. Right-align numeric columns.
- Letter-spacing: leave body at the font default. For all-caps labels add `tracking-wide`
  (`+0.05em`). For large display headings add `tracking-tight` (`-0.01em`).

## Color

- Define the full palette up front in DESIGN.md; never invent a shade at use-time.
- Consume semantic tokens; never hardcode hex inside a component. The 17 token names are defined
  in [DESIGN.md](../DESIGN.md).
- Never put neutral `text-fg-muted` on a colored surface. Use the matching `on-*` token instead
  (`text-on-primary` on `bg-primary`, `text-on-destructive` on `bg-destructive`).
- Use saturated color sparingly, for the one thing that must stand out. Most hierarchy comes from
  contrast, weight, and spacing.
- Never rely on color alone for state: pair with an icon or label. See
  [accessibility-wcag.md](accessibility-wcag.md).

## Depth and finishing polish

- Light comes from above: if using shadows, they fall downward. Assign shadows by role:
  - Cards, inputs: `shadow-sm`
  - Dropdowns, tooltips: `shadow-md`
  - Modals, popovers: `shadow-lg`
- Design grayscale-first. If the hierarchy reads without color, color reinforces it; if it only
  works with color, fix spacing/contrast first.
- Use fewer borders. Separate with a background-contrast shift (`bg-surface` vs
  `bg-surface-container`), a subtle shadow, or extra spacing before reaching for
  `border-color-border`.
- Add finishing touches:
  - Accent borders: a coloured strip on a card or alert, where the design allows one.
  - Designed empty states: icon, title, one clear action. Never ship a bare "No results". And
    distinguish "caught up" from "not started": both render as zero and they are different situations,
    the second being a first-run user deciding whether the setup is worth their afternoon.
  - Designed loading states matching the real layout shape. Do not show a spinner where the structure
    is known, and do not use a generic bar: **the placeholder is the row's own shadow**, the same
    component with the same geometry, so it cannot drift and the list does not jump when content
    lands. A stack of equal bars under a list of thumbnails and figures says nothing about what is
    arriving.

The empty-state component is in `magic_starter`; `docs/component-registry.md` names it.

## How to apply in this codebase

- Hierarchy: the type step from `DESIGN.md`, plus `font-semibold` and `text-fg` against
  `text-fg-muted` for contrast tiers. Reserve `bg-primary` for the single primary action per view.
- Spacing: use the 4px Wind scale (`gap-4`/`p-4`/`gap-6`) and keep inside < between < section.
  Wrap a text column in a `ConstrainedBox`; leave page width to the shell.
- Colour: consume the semantic roles. On a coloured surface use the matching `on-*` token; never
  `text-fg-muted` on a filled background. Never let colour carry meaning alone, and that includes
  selection state, not only status.
- Depth: take the radius from `DESIGN.md` and subtract the padding for anything nested. Prefer a
  surface-contrast shift or spacing before reaching for a border.
- Polish: build the mockup with realistic data first, at the hardest case rather than the happy one.
  Always design the empty and loading state of any list or async surface, and see both appearances
  before calling it done.

## See also

- [DESIGN.md](../DESIGN.md): this app's own token values, type scale, spacing scale and material rules
- [.claude/rules/design.md](../../.claude/rules/design.md): the measured anti-patterns, each with what it cost
- [accessibility-wcag.md](accessibility-wcag.md): contrast requirements
- [material-design-3.md](material-design-3.md): M3 role-to-token mapping
- [wind-responsive.md](wind-responsive.md): breakpoints and page geometry
- [motion-interaction.md](motion-interaction.md): loading states, skeletons, transition patterns

## Sources

- "Refactoring UI" by Adam Wathan and Steve Schoger (refactoringui.com).
- Flutter documentation: ConstrainedBox, TextStyle, MediaQuery.
- Wind token documentation: semantic aliases, 4px spacing scale.
