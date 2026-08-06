import 'package:magic/magic.dart';

/// Builds the [WindSlotRecipe] for the ProductRow component.
///
/// One product in a list, which is a different shape from `LocationStockRow`: that
/// one answers "how much is at this location" for a single product, this one answers
/// "what is this product and how much is there in total" across every location.
///
/// `min-w-0` on the body is load-bearing. Without it a `truncate` inside a nested
/// flex has no bounded width and a long product name overflows instead of clipping,
/// which is the most common failure in a list of user-entered names.
///
/// The whole row is a tap target, so `min-h-11` enforces the 44pt floor rather than
/// leaving it to whatever the content happens to measure.
WindSlotRecipe productRowRecipe() {
  return const WindSlotRecipe(
    slots: {
      'root': 'flex flex-row items-center gap-3 py-2 min-h-11',
      'thumb': 'size-10 rounded-md bg-surface-container-high flex items-center justify-center',
      'body': 'flex flex-col gap-0.5 flex-1 min-w-0',
      'name': 'text-sm font-semibold text-fg truncate',
      'meta': 'text-xs text-fg-muted truncate',
      'trailing': 'flex flex-col items-end gap-1',
    },
    variants: {
      'state': {
        'stocked': {'root': 'flex flex-row items-center gap-3 py-2 min-h-11'},
        'depleted': {
          'root': 'flex flex-row items-center gap-3 py-2 min-h-11',
          'name': 'text-sm font-semibold text-fg-muted truncate',
        },
      },
    },
    defaultVariants: {'state': 'stocked'},
  );
}
