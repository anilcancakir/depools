import 'package:magic/magic.dart';

/// Builds the [WindSlotRecipe] for the ShoppingRow component.
///
/// **Two states, and the checked one is not a completion.** Ticking a line in a shop means
/// the thing is in the trolley, not that stock arrived (D47), so a ticked row recedes
/// rather than vanishing: the list is still being walked and a line the user needs to
/// un-tick has to remain findable. It also has to stay countable, because what closes the
/// list is the receipt, and the receipt reconciles against the whole list.
///
/// The quantity keeps full weight in both states. It is what the user reads at the shelf,
/// and a ticked line is exactly the one they are holding in their hand while they check the
/// number.
WindSlotRecipe shoppingRowRecipe() {
  return const WindSlotRecipe(
    slots: {
      'root': 'flex flex-row items-start gap-3 py-2',
      'box':
          'size-6 shrink-0 rounded-md border border-color-border flex items-center justify-center',
      'boxIcon': 'size-4 text-fg-disabled',
      'body': 'flex flex-col gap-0.5 flex-1 min-w-0',
      'name': 'text-sm font-semibold text-fg truncate',
      'reason': 'flex flex-row items-center gap-1.5',
      'reasonText': 'text-xs text-fg-muted truncate',
      'trailing': 'axis-min',
    },
    variants: {
      'state': {
        'open': {},
        'checked': {
          'box': 'size-6 shrink-0 rounded-md bg-primary flex items-center justify-center',
          'boxIcon': 'size-4 text-on-primary',
          'name': 'text-sm font-semibold text-fg-muted truncate',
        },
      },
    },
    defaultVariants: {'state': 'open'},
  );
}
