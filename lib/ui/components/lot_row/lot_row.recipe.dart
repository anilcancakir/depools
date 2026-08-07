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
      'product': 'text-sm font-semibold text-fg truncate',
      'meta': 'flex flex-row items-center gap-2',
      'code': 'font-mono text-xs text-fg-muted truncate',
      'received': 'text-xs text-fg-muted',
      // The AÇIK marker. Uppercase and mono-adjacent so it reads as a state rather
      // than as a word in a sentence, and tinted with the expiring family because an
      // open lot IS on a clock (D27) even when its printed date is far off.
      'openTag': 'text-xs font-medium uppercase tracking-wide text-expiring',
    },
    variants: {
      'state': {
        'active': {'root': ''},
        // An open lot is not styled differently as a whole. It carries the AÇIK tag
        // and its own date, and that is enough: fading or tinting the entire row
        // would compete with the depleted treatment, and a user scanning for what to
        // use first needs the dates to be the thing that varies.
        'depleted': {'root': 'opacity-50'},
      },
    },
    defaultVariants: {'state': 'active'},
  );
}
