import 'package:magic/magic.dart';

/// Builds the [WindSlotRecipe] for the SectionHeader component.
///
/// A section head inside a screen, not a page title: `MSPageHeader` already owns
/// the page title and its `xl` type, so this sits a step below at `text-xs`
/// uppercase, the way an iOS grouped-list header does.
///
/// The label weight is `font-medium`, matching `StatCard`'s caption and
/// `MSSettingsSection`'s upstream. An earlier `font-semibold` gave the app two
/// weights for one micro-caption role, visible four lines apart on the product
/// screen, and the next screen would have copied whichever it saw last.
///
/// The count sits beside the label on the LEFT, not in the trailing slot. Putting
/// both a count and an action on the right crowded them into looking like one
/// element, and the count is a continuation of the label ("Hareketler, 9 kayıt")
/// while the action is a separate affordance. Right side is reserved for something
/// tappable.
///
/// The `trailing` slot holds the two right-hand slots side by side, so a section
/// that carries both an action and a state indicator keeps them on one baseline
/// instead of letting the indicator push the action off the row.
WindSlotRecipe sectionHeaderRecipe() {
  return const WindSlotRecipe(
    slots: {
      'root': 'flex flex-row items-center justify-between gap-2 min-h-11',
      'leading': 'flex flex-row items-baseline gap-2 flex-1 min-w-0',
      // **The label holds its width and the count gives way, and until now neither could.**
      // `leading` is `flex-1 min-w-0`, so it shrinks correctly when a trailing action is present,
      // but its two children were both intrinsically sized: `count` carried `truncate`, which sets
      // ellipsis overflow and does NOT make a Text shrinkable inside a Row. So the pair overflowed
      // the space `leading` had been given, by 25 pixels on one card and 11 on another at 390px,
      // and the amount varied with the label rather than with anything obvious.
      //
      // The label is the section's name and is never long, so it keeps its width. The count is a
      // secondary figure and is the right thing to ellipsize, so it takes the remaining space and
      // truncates inside it. Proven by substitution: one-character action labels made both
      // overflows vanish, which located the fault in this row rather than in the action.
      'label': 'text-xs font-medium uppercase tracking-wide text-fg-muted shrink-0',
      'count': 'text-xs font-medium text-fg-disabled truncate flex-1 min-w-0',
      'trailing': 'flex flex-row items-center gap-1 axis-min',
    },
    variants: {},
  );
}
