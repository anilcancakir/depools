import 'package:magic/magic.dart';

/// Builds the [WindSlotRecipe] for the LocationStockRow component.
///
/// Shows how much of one product sits at one location. A product's stock is split
/// across locations by design, so a detail screen repeats this row rather than
/// showing a single total: "3 in the garage, 2 in the kitchen" is the answer the
/// user came for, and a total of 5 hides it.
///
/// `min-w-0` on the leading column is load-bearing. Without it a `truncate` inside
/// a nested flex has no bounded width and the path overflows instead of clipping.
WindSlotRecipe locationStockRowRecipe() {
  return const WindSlotRecipe(
    slots: {
      'root': 'flex flex-row items-center justify-between gap-3 py-2',
      'leading': 'flex flex-col gap-0.5 flex-1 min-w-0',
      'path': 'text-sm font-medium text-fg truncate',
      'meta': 'text-xs text-fg-muted',
      'trailing': 'flex flex-col items-end gap-1',
    },
    variants: {
      'state': {
        'stocked': {'root': ''},
        'empty': {'root': '', 'path': 'text-sm font-medium text-fg-muted truncate'},
      },
    },
    defaultVariants: {'state': 'stocked'},
  );
}
