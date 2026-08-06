import 'package:magic/magic.dart';

/// Builds the [WindSlotRecipe] for the ListFooter component.
///
/// The three states a paginated list can end in, and they must not look alike: more
/// coming, nothing more, or it broke. A list that silently stops looks identical to one
/// that finished, and the user's only signal is a scroll that stops paying out.
///
/// `end` is deliberately quiet. Reaching the end of a list is not news, and a loud
/// "that's everything" competes with the rows above it. It states the total, because that
/// number is the one thing worth having there: it is also the SKU count the plan meters
/// on, so a user glancing at it learns something they otherwise have to hunt for.
WindSlotRecipe listFooterRecipe() {
  return const WindSlotRecipe(
    slots: {
      'root': 'flex flex-col items-center gap-2 py-4',
      'text': 'text-xs text-fg-muted',
      'error': 'text-sm text-fg',
    },
  );
}
