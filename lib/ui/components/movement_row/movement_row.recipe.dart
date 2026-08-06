import 'package:magic/magic.dart';

/// Builds the [WindSlotRecipe] for the MovementRow component.
///
/// One entry in the append-only ledger. The direction axis tints the delta and its
/// icon, and `waste` is its own direction rather than a flavour of outbound: waste
/// percentage and sell-through before expiry are computed by filtering on exactly
/// that distinction, so it has to be visible here too or the UI would imply a
/// distinction the data does not make.
///
/// The delta itself is rendered by `Quantity`, which owns mono value-plus-unit
/// everywhere in the app; only the icon is tinted from here. The delta keeps its
/// sign in the text rather than relying on colour, so the direction survives for a
/// user who cannot separate the tints.
///
/// **A reversed entry fades but keeps its place** (D51). It is not removed and not
/// collapsed into the correction that reversed it: the ledger is append-only, both
/// rows exist, and `forecasting.md` asks for balances that reconcile against the
/// visible history by hand. A history that hid half its own arithmetic would fail
/// that on the first check. Fading is `opacity-50`, the same treatment a rejected
/// receipt line gets, and for the same reason: still there, no longer counting.
WindSlotRecipe movementRowRecipe() {
  return const WindSlotRecipe(
    slots: {
      'root': 'flex flex-row items-center justify-between gap-3 py-2',
      'leading': 'flex flex-row items-center gap-2 flex-1 min-w-0',
      'icon': 'size-4',
      'body': 'flex flex-col gap-0.5 flex-1 min-w-0',
      'reason': 'text-sm font-medium text-fg truncate',
      'meta': 'text-xs text-fg-muted truncate',
      'note': 'text-xs text-fg-disabled',
      'trailing': 'flex flex-row items-center gap-2 axis-min',
    },
    variants: {
      'direction': {
        'inbound': {'icon': 'size-4 text-in-stock'},
        'outbound': {'icon': 'size-4 text-fg-muted'},
        'waste': {'icon': 'size-4 text-wasted'},
        'correction': {'icon': 'size-4 text-fg-muted'},
      },
      'state': {
        'live': {},
        // The note keeps full foreground weight under the fade. `text-fg-disabled` at
        // 50% opacity is not readable, and "Geri alındı" is the one thing this row still
        // has to say: the fade is for the data, not for the reason it faded.
        'reversed': {
          'root': 'flex flex-row items-center justify-between gap-3 py-2 opacity-50',
          'note': 'text-xs text-fg',
        },
      },
    },
    defaultVariants: {'direction': 'outbound', 'state': 'live'},
  );
}
