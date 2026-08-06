import 'package:magic/magic.dart';

/// Builds the [WindSlotRecipe] for the SerialRow component.
///
/// The mirror of `lotRowRecipe`, and the differences are deliberate.
///
/// **The serial is the primary text, in mono at `text-sm`.** On a lot row the
/// quantity is the figure that matters and the batch code is a muted aside; here the
/// serial IS the unit's identity, so it takes the weight. Mono because a serial gets
/// read aloud, typed back in and compared character by character, which is exactly
/// what a fixed-width face is for.
///
/// There is no quantity slot. A serial-tracked unit is present or it is not, so a
/// figure of "1" beside every row would be noise.
///
/// `gone` fades rather than hides, matching a depleted lot: a unit that has left is
/// the evidence behind the history, and dropping it would make the ledger look like
/// it lost entries.
WindSlotRecipe serialRowRecipe() {
  return const WindSlotRecipe(
    slots: {
      'root': 'flex flex-row items-center justify-between gap-3 py-2 min-h-11',
      'leading': 'flex flex-col gap-1 flex-1 min-w-0',
      'serial': 'font-mono text-sm text-fg truncate',
      'meta': 'text-xs text-fg-muted',
      'trailing': 'flex flex-row items-center gap-2 axis-min',
    },
    variants: {
      'state': {
        'present': {'root': 'flex flex-row items-center justify-between gap-3 py-2 min-h-11'},
        'gone': {
          'root': 'flex flex-row items-center justify-between gap-3 py-2 min-h-11 opacity-50',
        },
      },
    },
    defaultVariants: {'state': 'present'},
  );
}
