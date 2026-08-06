import 'package:magic/magic.dart';

/// Builds the [WindSlotRecipe] for the SectionCard component.
///
/// The card chrome here was copied by hand into every section of both product
/// screens before this component existed: eight occurrences of
/// `flex flex-col gap-1 p-4 rounded-lg bg-surface-container`, which is eight
/// chances for one section to drift a gap or a radius away from its neighbours.
///
/// `gap-1` between rows rather than something larger is deliberate: the rows carry
/// their own `py-2` and a `min-h-11` floor, so their padding does the separating. A
/// bigger gap on top of that reads as a list of cards instead of a list of rows.
///
/// The collapsed state is not represented here. Wind's `hidden` still builds its
/// child (it returns a `SizedBox.shrink` around it), so a collapsed section of two
/// hundred rows would keep paying to build them. The widget omits the body slot
/// instead, which is why there is no `collapsed` variant to style.
WindSlotRecipe sectionCardRecipe() {
  return const WindSlotRecipe(
    slots: {
      'root': 'flex flex-col gap-1 p-4 rounded-lg bg-surface-container',
      'body': 'flex flex-col gap-1',
      'chevron': 'size-5 text-fg-muted',
    },
  );
}
