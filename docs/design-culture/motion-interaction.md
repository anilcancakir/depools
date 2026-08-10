# Motion and interaction (Flutter/Wind reference)

Read this when adding any animation or interactive feedback to a screen. The 2026 consensus is
restraint: subtle, fast, purposeful. Motion you notice is usually wrong.

> **Motion is mostly Dart here, not className.** Wind's motion surface is narrow, and the tokens it
> does NOT have fail silently rather than loudly: an unknown prefix or family drops the whole class
> (`wind_parser.dart`), so a className that looks like a press animation or a reduced-motion guard can
> do nothing at all while reading as correct. The table below is what wind actually parses; everything
> else goes through Flutter's animation APIs.

## When to animate (and when not)

Animate only for a reason: feedback (confirm an action), continuity (connect states), spatial
orientation (where did this come from), or guiding attention. Everything else is decoration; cut it.

Frequency rule: the more often an action repeats, the less it should animate.

| Frequency | Guideline |
|---|---|
| 100+ per day (toggles, tab switches) | No animation, instant |
| Tens per day (hover, nav item tap) | Minimal, <=150ms |
| Occasional (modals, drawers, toasts) | Standard animation |
| Rare / first-run (onboarding, empty state) | A little delight is allowed |

## Easing

In Flutter, easing maps to `Curve` values in `CurvedAnimation`:

| Intent | Flutter Curve | Approximate bezier |
|---|---|---|
| Element entering | `Curves.easeOut` | cubic-bezier(0.23, 1, 0.32, 1) |
| Material entering | `Curves.easeOutCubic` | cubic-bezier(0.05, 0.7, 0.1, 1) |
| Moving / morphing | `Curves.easeInOut` | cubic-bezier(0.2, 0, 0, 1) |
| Element exiting | `Curves.easeIn` | acceptable ONLY for exits |
| Continuous (spinner) | `Curves.linear` | linear |

Never use `Curves.easeIn` for entering UI; it delays movement exactly when the user is watching.

## Durations

Exit animations should be 20-30% faster than their enter counterpart.

| Category | Duration |
|---|---|
| Micro (button press, tooltip, hover) | 100-200ms (press feedback 75-100ms) |
| Standard (dropdown, popover, select) | 200-300ms |
| Large (modal, drawer, route transition) | 300-500ms |
| Hard cap for UI feedback | 300ms |

```dart
// Standard dropdown
AnimatedContainer(
  duration: const Duration(milliseconds: 200),
  curve: Curves.easeOut,
  ...
)

// Large modal enter
PageRouteBuilder(
  transitionDuration: const Duration(milliseconds: 350),
  ...
)
```

## Micro-interactions: what wind can and cannot express

Every interactive element has six states: default, hover (desktop), focused, pressed, disabled,
loading. A missing loading or disabled state is the most common quality gap.

What wind parses, verified against its own source:

| Want | Wind token | Status |
|---|---|---|
| Hover shift | `hover:bg-*`, `hover:opacity-*` | works; `WAnchor` gates hover behind pointer detection |
| Focus ring | `focus:ring-2 focus:ring-primary`, `ring-offset-*` | works |
| Disabled dimming | `disabled:opacity-50` | works |
| Duration and easing | `duration-{75..1000}`, `duration-[Nms]`, `ease-*` | works (`transition_parser`) |
| Looping shimmer or spinner | `animate-pulse`, `animate-spin` | works (`animation_parser`) |
| A named transition family | `transition-colors`, `transition-all` | **NOT parsed.** `canParse` accepts only `duration-` and `ease-` |
| Press feedback | `active:*` | **prefix reserved, not wired.** `WAnchor` tracks hover and focus only; there is no onTapDown/onTapUp |
| Scale or translate | `scale-95`, `translate-x-*` | **no transform parser exists** |
| Keyboard-only focus | `focus-visible:` | **not a wind state.** Only `hover`/`focus`/`disabled` come from a prefix |
| Reduced-motion gate | `motion-safe:` | **not a wind state** |

The four NOTs are why the state list below is expressed in Dart:

- **Press.** If you genuinely need press feedback, carry it as a transient state in the caller and
  pass `states: {'pressed'}`, with a `pressed:` class in the className. Custom states DO work; the
  built-in `active:` does not.
- **Focus.** Use `focus:`. Wind has no keyboard-only distinction, so the ring appears on pointer focus
  too; that is the tradeoff, not a bug to work around with a prefix that does not exist.
- **Reduce Motion.** Guard in Dart with `MediaQuery.of(context).disableAnimations`.
- **Disabled.** `disabled:opacity-50` works, and also pass the widget's own `disabled`/`onPressed:
  null` so the gesture is actually blocked. Note that dimming alone may not read: measured in this
  theme, a disabled button in the primary intent looks live, which is why the app's rule is to remove
  the control or state the blocking reason rather than to grey it out.
- **Loading.** Show a spinner or a skeleton; never disable without visual feedback.

## Overlays and transitions in Flutter

For modals, bottom sheets, and drawers, Flutter's built-in route system handles the animation
curve. Customize via `PageRouteBuilder` or `showModalBottomSheet` parameters:

```dart
// Bottom sheet: slide up from bottom, ease-out
showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  transitionAnimationController: AnimationController(
    duration: const Duration(milliseconds: 300),
    vsync: this,
  ),
  builder: (_) => BottomSheetContent(),
)
```

For in-page expand/collapse (accordion, inline panel):

```dart
AnimatedSize(
  duration: const Duration(milliseconds: 200),
  curve: Curves.easeOut,
  child: isExpanded ? ExpandedContent() : const SizedBox.shrink(),
)
```

Pattern: opacity + small directional slide toward the trigger gives spatial context. Keep
tooltip/dropdown entrances 100-150ms.

## Route transitions

`magic` routes over `go_router`. Route transitions use `CustomTransitionPage`:

```dart
CustomTransitionPage(
  child: const DashboardView(),
  transitionsBuilder: (context, animation, secondaryAnimation, child) {
    return FadeTransition(opacity: animation, child: child);
  },
  transitionDuration: const Duration(milliseconds: 250),
)
```

Auth routes use `RouteTransition.none` (no animation between auth screens). For content
screens a simple fade (150-250ms, `Curves.easeOut`) is the safest default.

## Loading and skeleton states

- Show a placeholder within ~300ms if data has not arrived.
- **The placeholder is the row's own shadow, not a generic bar.** Same component, same geometry, so it
  cannot drift from what arrives and the list does not jump when content lands: this app's convention
  is a named constructor on the real row (`ProductRow.skeleton()`). A stack of equal bars under a list
  of thumbnails and figures says nothing about what is coming, and it is listed as an anti-pattern in
  `.claude/rules/design.md`. Only the caller knows the shape, so a shared footer takes it from the
  caller rather than guessing.
- Render as many placeholder rows as the page size, so the space is reserved.
- Reserve spinners for short blocking mutations (submit, auth).
- `animate-pulse` is parsed and works. It cannot be gated in className, because `motion-safe:` is not
  a wind state, so a reduced-motion build swaps the pulsing placeholder for a static one in Dart:

```dart
final reduceMotion = MediaQuery.of(context).disableAnimations;

WDiv(className: reduceMotion
    ? 'bg-surface-container-high rounded'
    : 'animate-pulse bg-surface-container-high rounded')
```

Two fixed classNames rather than one interpolated string, because Core Law 3 forbids interpolating a
computed value into a className and two literals keep the parser cache to two entries.

## Performance in Flutter

- Animate ONLY properties handled by the compositor: `opacity`, `transform` (via `Transform` or
  `AnimatedContainer`). Avoid animating `width`, `height`, `padding`, or `margin` (layout pass
  every frame).
- Use `RepaintBoundary` around complex animated subtrees to isolate repaints.
- Avoid many simultaneous animations in one viewport. Use `ListView.builder` or
  `SliverList` for long off-screen lists; Flutter will tree-shake non-visible widgets.
- `TickerProviderStateMixin` properly disposes controllers; always call `controller.dispose()`
  in `State.dispose()`.

## Accessibility and restraint

Respect the OS "Reduce Motion" setting via `MediaQuery.of(context).disableAnimations`:

```dart
final reduceMotion = MediaQuery.of(context).disableAnimations;

// Skip or make instant when reduced
controller.duration = reduceMotion
    ? Duration.zero
    : const Duration(milliseconds: 200);
```

This is the ONLY place the gate can live. There is no className form of it here, and a className that
appears to provide one is dropped without a warning.

Disable under reduced motion: parallax, scale/zoom, large pan/translate, looping autoplay,
staggered reveals, shimmer. Keep or substitute: opacity fades, color transitions, instant snap.
Substitute, do not just delete, motion that conveys state (for example, replace a spinner with a
static icon when motion is disabled, do not hide loading state entirely).

No content flashes more than 3 times per second. Auto-playing motion over 5 seconds needs a
pause control.

## Per-screen motion checklist

Before marking any screen done:

1. Every animated element guards against reduced motion via `MediaQuery.of(context).disableAnimations`.
2. Only `opacity` and `transform` animate; no layout-triggering properties.
3. Entrances `Curves.easeOut`; exits faster; no `Curves.easeIn` on entrances.
4. UI feedback under 200ms; large transitions under 500ms.
5. Six interactive states present (default, hover, focus, pressed, disabled, loading), and each one
   actually reachable: a `states:` set for pressed, `focus:` for focus, and a real visual difference
   for disabled rather than an opacity that does not read.
6. Auto-play is controllable; nothing flashes >3 times/sec.
7. Every motion token in a className is one the table above lists as working. A dead token looks
   identical to a live one in source.

## See also

- [DESIGN.md](../DESIGN.md): brand personality and DESIGN.md motion direction
- [accessibility-wcag.md](accessibility-wcag.md): WCAG 2.2.2 / 2.3.1 reduced-motion requirements
- [wind-responsive.md](wind-responsive.md): safe-area, layout transitions
- [apple-hig.md](apple-hig.md): Apple spring-based motion feel
- [material-design-3.md](material-design-3.md): M3 easing tokens

## Sources

- Emil Kowalski / animations.dev (easing + duration tables, frequency rule).
- Material Design 3 motion: easing/duration tokens (m3.material.io/styles/motion).
- Apple HIG motion (developer.apple.com); WWDC23 "Animate with springs".
- Flutter documentation: CurvedAnimation, AnimationController, AnimatedContainer, AnimatedSize,
  MediaQuery.disableAnimations, RepaintBoundary.
- WCAG 2.2: 2.2.2 / 2.3.1 / 2.3.3.
