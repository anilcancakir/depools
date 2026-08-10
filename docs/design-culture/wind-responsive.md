# Wind responsive layout (Flutter reference)

Read this when building any screen layout. Wind's responsive system is breakpoint-prefix-driven,
not CSS media-query-driven. This doc covers breakpoints, page geometry, safe-area handling,
navigation layout patterns, hit targets, and mobile-first rules.

## Breakpoints

Wind's defaults, from `wind/lib/src/theme/defaults/screens.dart`. They apply to the logical viewport
width reported by `MediaQuery.of(context).size.width`:

| Prefix | Min width | Typical device |
|---|---|---|
| (none, default) | 0px | All screens, mobile first |
| `sm:` | 640px | Large phones, landscape |
| `md:` | 768px | Tablets |
| `lg:` | 1024px | Desktop |
| `xl:` | 1280px | Wide desktop |
| `2xl:` | 1536px | Very wide |

A theme may add its own keys, so check the app's `WindThemeData` before assuming this is the whole
set.

Breakpoints are mobile-first: a class without a prefix applies to ALL widths; a prefixed class
overrides from that breakpoint up.

```dart
// Single-column on mobile, two-column on md+
WDiv(
  className: 'flex flex-col md:flex-row gap-4',
  children: [MainContent(), Sidebar()],
)
```

Wind has no CSS `@media` query mechanism; the breakpoint resolution runs inside the Wind parser
using the current `MediaQuery` width. Do not try to use CSS media queries or `LayoutBuilder`
directly for layout decisions that are already expressible as Wind breakpoint prefixes.

## Page geometry belongs to the shell, not to the page

`magic_starter` constrains content width and horizontal gutters in ONE place, read from
`MagicStarter.manager.pageContainerClassName`. A page that carries its own cap disagrees with its
neighbours inside the same shell, and that drift is invisible until two screens sit side by side.

So: set it once during bootstrap, never per screen, and do not add extra horizontal padding inside
it. The cap and the gutter values this app uses are in `DESIGN.md`'s Layout section and are applied in
`lib/app/providers/app_service_provider.dart`.

Whether a page goes through a scaffold at all is also a project rule rather than a preference here:
`DESIGN.md` requires every page to go through `MSPageScaffold`, which owns the surface fill, the
scroll, the shared geometry and the header.

## Safe area handling

On iOS and Android, system UI (status bar, home indicator, notch) can overlap content. The shell
applies `SafeArea` at its own level, so a view rendered inside it does NOT re-wrap: a second
`SafeArea` inside the first inserts the inset twice and the page sits low by the height of the notch.

A full-screen surface mounted OUTSIDE the shell is the case that does need its own, because there is
nothing above it to have applied one.

For a viewport-anchored bottom control, account for the home indicator rather than a constant:

```dart
Padding(
  padding: EdgeInsets.only(
    bottom: MediaQuery.viewPaddingOf(context).bottom + 16,
  ),
  child: ActionButton(),
)
```

**And account for whatever else is anchored down there.** Two viewport-anchored controls in the same
corner is two primary actions, which is what Material objects to. The pattern in this app is that the
host MEASURES the pinned footer and folds its height into `MediaQuery.padding.bottom`, so anything
reading that padding lifts by the right amount and needs to know nothing about footers. A guessed
constant is wrong by construction as soon as one screen's footer is taller than another's.

Dialog safe area uses the modal formula: `safeHeight = screenHeight - top - bottom insets`,
then `maxHeight = safeHeight * 0.85`. `magic_starter`'s dialog and sheet components handle this
through `MediaQuery.viewPaddingOf(context)`.

## Navigation: sidebar vs bottom nav

The `AppLayout` shell switches navigation patterns at ONE breakpoint, and it is **`lg` (1024px)**,
not `md`. Verified in `magic_starter/lib/src/ui/layouts/magic_starter_app_layout.dart`, which reads
`wScreenIs(context, 'lg')` and branches the whole `Scaffold` on it:

| Width | Navigation pattern |
|---|---|
| Below 1024px | Bottom navigation bar + hamburger drawer |
| 1024px and above | Sidebar navigation rail |

This matters twice. A `md:hidden` pair written against the wrong assumption is correct at 390px and
1400px and wrong across the whole 768 to 1023 band, which is tablet portrait. And it decides where a
change has to be verified: 768px is still the MOBILE shell, so testing at 768 does not test the
sidebar. `docs/verification-loop.md` lists the widths to use.

The two sides are different widget trees, so each can break alone.

To implement the same switch in a custom layout:

```dart
// Show sidebar on desktop, hide on mobile
WDiv(
  className: 'hidden lg:flex flex-col w-64 bg-surface-container border-r border-color-border',
  children: [SidebarContent()],
)

// Show bottom nav below the switch, hide above it
WDiv(
  className: 'flex lg:hidden flex-row bg-surface-container border-t border-color-border',
  children: [BottomNavItems()],
)
```

Never show both a sidebar and a bottom nav at the same width. Below the switch, the sidebar appears
as a drawer (`Drawer` + `Scaffold.drawer`).

The bottom nav has NO fixed height: it is item content plus the device's safe area. Anything that has
to clear it measures, rather than assuming a constant.

## 44px hit targets

Every interactive element must have a minimum 44x44 logical-px hit target (Apple HIG asks 44,
Material 48; WCAG 2.5.8's floor is 24px). Pad invisibly rather than shrink the control.

`min-h-11` is 44px and is the right tool on a plain `WDiv`. **It is not universally right**: on a
`magic_starter` button it grows the box downward without re-centring the label, measured 4 logical px
off, so padding is the technique there and the arithmetic has to be checked against the button's own
size. `.claude/rules/design.md` carries the per-control answer and the measurements behind it.

For an icon-only control, reserving the box in Flutter is unambiguous:

```dart
SizedBox(
  width: 44,
  height: 44,
  child: Center(child: Icon(Icons.close, size: 20)),
)
```

Bottom nav and sidebar items are interactive too and get the same floor.

**Two controls side by side in one row must be pinned to the same explicit height.** A row reads as
one control, so `items-center` centres the mismatch rather than hiding it. Measured: a search field
at 52 next to its filter button at 44.

## Mobile-first composition rules

1. Start with the mobile layout (no prefix). Confirm it reads at **390px**, in a fixed-width frame
   rather than by narrowing the window: the preview catalog keeps its sidebar at every width, so
   narrowing squeezes the harness instead of the screen.
2. Add `md:` or `lg:` overrides for wider changes (column -> row, hidden -> shown). Pick the prefix
   from where the layout actually breaks, and remember which one the shell itself switches on.
3. Never write `sm:hidden` or `sm:flex` as the primary display rule; start mobile-visible, then
   hide at breakpoints.
4. Branch on WIDTH, never on platform. `ios:`/`android:`/`web:` exist in wind and are the wrong tool
   for layout; `DESIGN.md` forbids them for it outright.

```dart
// Correct: visible by default, hidden on desktop
WDiv(className: 'flex lg:hidden', children: [MobileMenu()])

// Correct: hidden by default (inline), visible on desktop
WDiv(className: 'hidden lg:flex', children: [Sidebar()])
```

## Text and content constraints

Do not fill available width with text. Constrain reading columns:

```dart
ConstrainedBox(
  constraints: const BoxConstraints(maxWidth: 600),
  child: WText(longBodyText, className: 'text-fg body-md'),
)
```

Inside the shell's container, text naturally hits the container max-width, which is a cap rather than
a reading column. For an individual narrow column (an auth form, a settings card) apply an inner
`ConstrainedBox`.

## WindRecipe with responsive variants

When a component has a layout-responsive variant, express it in the recipe's `className` caller
rather than as a recipe variant axis. Responsive breakpoints are caller context, not component
internals:

```dart
// Caller supplies the responsive layout via className
SomeCard(
  className: 'w-full md:w-1/2 lg:w-1/3',
  child: ...,
)
```

The `WindRecipe` base and variant tokens handle visual state (tone, size, intent). Responsive
width is caller responsibility.

## Platform prefixes

Wind provides platform prefixes: `ios:`, `android:`, `web:`, `mobile:`, `macos:`, `windows:`,
`linux:`.

**They are not a layout tool.** A responsive layout branches on width; a platform prefix branches on
the device, which produces two arrangements that neither can be reviewed against the other nor
verified by resizing. `DESIGN.md` rules them out for layout entirely and states the positive form: one
app, one feature set, layout adapts to WIDTH, and where hardware genuinely differs the app uses what
the platform offers rather than dropping the feature.

## Two layout shapes that fail without naming themselves

Both cost a debugging cycle in this app, and neither error message points at the cause.

**A page cannot divide its own height.** The shell puts every route inside
`WDiv(className: 'flex-1 overflow-y-auto')`, so a page is handed UNBOUNDED height: `Column` plus
`Expanded` fails as `RenderBox was not laid out`, and `h-full` resolves to infinity. The same fact
means a `Positioned` mounted from inside a page anchors to the bottom of the scrolled CONTENT rather
than to the viewport, so it renders nothing and throws nothing. Anything viewport-anchored mounts
OUTSIDE the shell; see `lib/ui/layouts/page_chrome.dart`.

**Anything mounted outside the shell loses its `Material` ancestor**, and every string then renders in
Flutter's yellow double-underlined fallback. It looks like a theme bug. Wrap it in
`Material(type: MaterialType.transparency)` and let a wind box paint the fill.

## See also

- [DESIGN.md](../DESIGN.md): the spacing scale, the gutters, the content cap, and the width-not-platform rule
- [.claude/rules/design.md](../../.claude/rules/design.md): the measured layout anti-patterns, with what each one cost
- [docs/verification-loop.md](../verification-loop.md): which widths to verify at, and how to resize correctly
- [accessibility-wcag.md](accessibility-wcag.md): hit targets, SafeArea requirements
- [material-design-3.md](material-design-3.md): navigation by breakpoint (M3 guidance)
- [apple-hig.md](apple-hig.md): screen-edge margins, concentric radii
- [refactoring-ui.md](refactoring-ui.md): whitespace, text column constraints

## Sources

- magic_starter `AppLayout` and `GuestLayout` source (`lib/src/ui/layouts/`).
- Wind breakpoint prefix documentation (`wind/CLAUDE.md`).
- Flutter documentation: MediaQuery, SafeArea, Scaffold.drawer, ConstrainedBox.
- Apple HIG Layout guidelines; Material 3 navigation components.
