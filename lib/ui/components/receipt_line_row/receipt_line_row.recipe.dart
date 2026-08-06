import 'package:magic/magic.dart';

/// Builds the [WindSlotRecipe] for the ReceiptLineRow component.
///
/// The four states are `receipt_lines.resolution_state` from `data-model.md`, not the
/// UI's own vocabulary: `unresolved`, `matched`, `created`, `rejected`. Naming them
/// anything else here would need a translation layer at the API boundary, which is the
/// mistake the stock-out reason enum already made once.
///
/// **`matched` and `created` are both settled and look alike on purpose.** The user does
/// not care whether a line found an existing product or minted a new one; they care
/// whether it needs them. The distinction shows in the meta line, not in the row's
/// weight, because a screen that visually separates two settled states makes the
/// nineteen lines that are FINE look like nineteen decisions.
///
/// `unresolved` is the one that has to pull the eye. It carries the `ai` tone, the same
/// one `DraftField` uses when the model gave up, because it is the same fact: the app
/// worked as far as it could and the rest is yours.
///
/// `rejected` fades rather than disappearing. A line the user dropped stays visible so
/// the receipt still reconciles against the paper in their hand, which is the whole
/// reason a receipt review is checkable.
WindSlotRecipe receiptLineRowRecipe() {
  return const WindSlotRecipe(
    slots: {
      'root': 'flex flex-row items-start gap-3 py-2',
      'body': 'flex flex-col gap-0.5 flex-1 min-w-0',
      'name': 'text-sm font-semibold text-fg truncate',
      'extracted': 'font-mono text-xs text-fg-muted truncate',
      'prompt': 'text-sm font-medium text-ai',
      'meta': 'text-xs text-fg-muted truncate',
      'trailing': 'flex flex-col items-end gap-0.5 axis-min',
    },
    variants: {
      'state': {
        'settled': {'root': 'flex flex-row items-start gap-3 py-2'},
        'unresolved': {'root': 'flex flex-row items-start gap-3 py-2'},
        'rejected': {'root': 'flex flex-row items-start gap-3 py-2 opacity-50'},
      },
    },
    defaultVariants: {'state': 'settled'},
  );
}
