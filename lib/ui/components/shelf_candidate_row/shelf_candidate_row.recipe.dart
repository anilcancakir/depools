import 'package:magic/magic.dart';

/// Builds the [WindSlotRecipe] for the ShelfCandidateRow component.
///
/// **The region number is the link to the photograph** (D60), so it is a fixed-width badge on
/// every row whatever the state. A shelf photo yields several crops and the only thing that
/// tells a user WHICH box on the picture a row belongs to is that both carry the same number.
/// It is also why the number is drawn rather than implied by order: rows get filtered and
/// reordered, boxes do not move.
///
/// Three looks for four states, and the pairing matches `ReceiptLineRow`'s: `matched` and
/// `created` are both settled and look alike, because a user reviewing six candidates cares
/// which ones need them rather than which ones found an existing product. `unresolved` takes
/// the `ai` tone, the same one every "the app got this far and the rest is yours" state uses.
/// `rejected` fades and stays, so a mis-tap is findable.
WindSlotRecipe shelfCandidateRowRecipe() {
  return const WindSlotRecipe(
    slots: {
      'root': 'flex flex-row items-start gap-3 py-2',
      'badge':
          'size-6 shrink-0 rounded-full bg-surface-container-high '
          'flex items-center justify-center',
      'badgeText': 'font-mono text-xs font-semibold text-fg',
      'body': 'flex flex-col gap-0.5 flex-1 min-w-0',
      'name': 'text-sm font-semibold text-fg truncate',
      'prompt': 'text-sm font-medium text-ai',
      'meta': 'text-xs text-fg-muted truncate',
      'trailing': 'axis-min',
    },
    variants: {
      'state': {
        'settled': {},
        'unresolved': {},
        'rejected': {'root': 'flex flex-row items-start gap-3 py-2 opacity-50'},
      },
    },
    defaultVariants: {'state': 'settled'},
  );
}
