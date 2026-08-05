import 'package:magic/magic.dart';

/// Builds the [WindSlotRecipe] for the SectionHeader component.
///
/// A section head inside a screen, not a page title: `MSPageHeader` already owns
/// the page title and its `xl` type, so this sits a step below at `text-xs`
/// uppercase, the way an iOS grouped-list header does.
///
/// The count sits beside the label on the LEFT, not in the trailing slot. Putting
/// both a count and an action on the right crowded them into looking like one
/// element, and the count is a continuation of the label ("Hareketler, 9 kayıt")
/// while the action is a separate affordance. Right side is reserved for something
/// tappable.
WindSlotRecipe sectionHeaderRecipe() {
  return const WindSlotRecipe(
    slots: {
      'root': 'flex flex-row items-center justify-between gap-2 min-h-11',
      'leading': 'flex flex-row items-baseline gap-2 flex-1 min-w-0',
      'label': 'text-xs font-semibold uppercase tracking-wide text-fg-muted',
      'count': 'text-xs font-medium text-fg-disabled truncate',
    },
    variants: {},
  );
}
