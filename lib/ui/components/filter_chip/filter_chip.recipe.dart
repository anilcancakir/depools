import 'package:magic/magic.dart';

/// Builds the [WindSlotRecipe] for the FilterChip component.
///
/// Two states, and the difference between them is the whole point of the
/// component. An `idle` chip is an offer: a saved filter you could apply. An
/// `applied` chip is a statement: this is narrowing the list right now. If those
/// two read alike, the user cannot tell why the list is short, which is the
/// documented reason mobile filtering fails (see
/// `docs/depools-system/features/filtering-and-saved-views.md`).
///
/// So `applied` is tinted with `bg-primary-container` and carries a border in the
/// brand tone, while `idle` sits on the card tone with a hairline border. The
/// tint is doing the work; the × icon is the confirmation, not the only signal,
/// because an icon that small is easy to miss in a scrolling row.
///
/// `rounded-full` rather than `rounded-md`: a capsule reads as a token you can
/// pick up and drop, which is what these are. `min-h-11` holds the 44pt floor even
/// though the type is `text-sm`, since every chip here is a tap target.
///
/// `axis-min` on the root is load-bearing. These chips live inside a scrolling
/// Row, and without it each one takes MainAxisSize.max and the first chip fills
/// the viewport.
WindSlotRecipe filterChipRecipe() {
  return const WindSlotRecipe(
    slots: {
      'root': 'flex flex-row items-center gap-1.5 px-3 min-h-11 rounded-full axis-min',
      'label': 'text-sm font-medium',
      'remove': 'size-4',
    },
    variants: {
      'state': {
        'idle': {
          // Card tone plus a hairline, never the input tone. `bg-surface-container-high` is
          // DESIGN.md's INPUT background: in dark mode it is lighter than its container and
          // reads as raised, but in light mode it is DARKER than a white card and reads as
          // recessed, which is the universal look of a disabled control. Elevation direction
          // flips between appearances, so only a border can say "pressable" in both.
          'root':
              'flex flex-row items-center gap-1.5 px-3 min-h-11 rounded-full axis-min '
              'bg-surface-container border border-color-border',
          'label': 'text-sm font-medium text-fg',
        },
        'applied': {
          'root':
              'flex flex-row items-center gap-1.5 px-3 min-h-11 rounded-full axis-min '
              'bg-primary-container border border-color-border',
          'label': 'text-sm font-medium text-fg',
          'remove': 'size-4 text-fg-muted',
        },
      },
    },
    defaultVariants: {'state': 'idle'},
  );
}
