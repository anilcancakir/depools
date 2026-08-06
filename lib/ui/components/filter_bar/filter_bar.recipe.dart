import 'package:magic/magic.dart';

/// Builds the [WindSlotRecipe] for the FilterBar component.
///
/// `overflow-x-auto` on the scroller with `axis-min` chips inside is what makes the
/// row scroll rather than wrap. Wrapping would look tidier at rest and is wrong: a
/// row that grows to three lines pushes the list itself off a phone screen, and the
/// number of chips is user-controlled, so there is no height to design for.
///
/// `gap-2` between chips, not `gap-1`. These are capsules with their own padding
/// and no border in the idle state, so a tight gap makes two chips read as one
/// segmented control.
WindSlotRecipe filterBarRecipe() {
  return const WindSlotRecipe(
    slots: {
      'root': 'flex flex-col gap-2',
      'scroller': 'flex flex-row items-center gap-2 w-full overflow-x-auto',
      // One treatment for both text actions. "Kaydet" left on MSButton's default
      // came out bright white beside a muted "Temizle", which read as an accident
      // rather than a hierarchy: they are the same kind of thing, a text action on
      // the end of the row, and neither should outrank the chips they follow.
      'textAction': 'text-sm font-medium text-fg-muted',
    },
  );
}
