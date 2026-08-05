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
WindSlotRecipe movementRowRecipe() {
  return const WindSlotRecipe(
    slots: {
      'root': 'flex flex-row items-center justify-between gap-3 py-2',
      'leading': 'flex flex-row items-center gap-2 flex-1 min-w-0',
      'icon': 'size-4',
      'body': 'flex flex-col gap-0.5 flex-1 min-w-0',
      'reason': 'text-sm font-medium text-fg truncate',
      'meta': 'text-xs text-fg-muted truncate',
    },
    variants: {
      'direction': {
        'inbound': {'icon': 'size-4 text-in-stock'},
        'outbound': {'icon': 'size-4 text-fg-muted'},
        'waste': {'icon': 'size-4 text-wasted'},
        'correction': {'icon': 'size-4 text-fg-muted'},
      },
    },
    defaultVariants: {'direction': 'outbound'},
  );
}
