import 'package:magic/magic.dart';

/// Builds the [WindSlotRecipe] for the CountRow component.
///
/// Three states, and the uncounted one is deliberately the quietest. A count sheet opens
/// with every row uncounted, so if that state carried a tone the whole screen would be
/// coloured before the user had done anything.
///
/// `matched` and `variance` both mean "counted", so they share the row's weight. Only the
/// verdict line differs: a match recedes and a variance takes the `low-stock` tone, because
/// a discrepancy is the one thing on this screen worth looking at twice.
///
/// The input keeps the card tone plus a hairline like every other tappable surface here.
/// `bg-surface-container-high` would be correct for an input well in isolation, but a row of
/// grey wells on a white card in light mode reads as a disabled form.
WindSlotRecipe countRowRecipe() {
  return const WindSlotRecipe(
    slots: {
      'root': 'flex flex-row items-center gap-3 py-2',
      'body': 'flex flex-col gap-0.5 flex-1 min-w-0',
      'name': 'text-sm font-semibold text-fg truncate',
      'verdict': 'text-xs text-fg-muted truncate',
      'field': 'w-20 axis-min',
      'unit': 'text-xs text-fg-muted axis-min',
    },
    variants: {
      'state': {
        'uncounted': {'verdict': 'text-xs text-fg-disabled truncate'},
        'matched': {'verdict': 'text-xs text-in-stock truncate'},
        'variance': {'verdict': 'text-xs text-low-stock truncate'},
      },
    },
    defaultVariants: {'state': 'uncounted'},
  );
}
