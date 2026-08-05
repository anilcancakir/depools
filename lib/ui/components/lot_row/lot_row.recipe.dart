import 'package:magic/magic.dart';

/// Builds the [WindSlotRecipe] for the LotRow component.
///
/// A lot is the unit of expiry: three cartons of milk bought on three days are
/// three lots, which is the whole reason a single expiry field on the product
/// cannot express reality.
///
/// `depleted` fades a lot whose remaining quantity reached zero. It stays in the
/// list rather than disappearing, because a consumed lot is the evidence behind
/// the consumption history, and hiding it would make the ledger look incomplete.
WindSlotRecipe lotRowRecipe() {
  return const WindSlotRecipe(
    slots: {
      'root': 'flex flex-row items-center justify-between gap-3 py-2',
      'leading': 'flex flex-col gap-1 flex-1 min-w-0',
      'meta': 'flex flex-row items-center gap-2',
      'code': 'font-mono text-xs text-fg-muted truncate',
      'received': 'text-xs text-fg-muted',
    },
    variants: {
      'state': {
        'active': {'root': ''},
        'depleted': {'root': 'opacity-50'},
      },
    },
    defaultVariants: {'state': 'active'},
  );
}
