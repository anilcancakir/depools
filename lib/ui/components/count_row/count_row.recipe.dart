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
      // Two lines, not one row. The verdict is a full-width statement rather than a column:
      // once the count fields took fixed widths the body narrowed enough to truncate
      // "500 ml eksik" off the end, and that phrase is the entire diagnostic content.
      'root': 'flex flex-col gap-0.5 py-2',
      'top': 'flex flex-row items-center gap-3',
      'name': 'text-sm font-semibold text-fg flex-1 min-w-0 truncate',
      'verdict': 'text-xs text-fg-muted',
      // Fixed widths, because this is a COLUMN and not a row of content. Sized to their
      // text, `adet` is wider than `ml` and a row with no opened-unit pair has two fewer
      // children, so the fields wandered left and right down the list. Anılcan caught it in
      // one glance: the same failure as a conditionally-rendered leading glyph, one axis
      // over, and the same fix (reserve the space whether or not it is used).
      'field': 'w-20 shrink-0',
      'unit': 'w-10 shrink-0 text-xs text-fg-muted',
      'plus': 'w-4 shrink-0 text-xs text-fg-muted text-center',
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
