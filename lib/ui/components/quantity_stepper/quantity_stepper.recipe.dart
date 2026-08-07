import 'package:magic/magic.dart';

/// Builds the [WindSlotRecipe] for the QuantityStepper component.
///
/// **One border, not three.** The first version put a bordered button, a bordered input and
/// another bordered button in a row with gaps: three heights, two corner radii, and nothing
/// tying them together. Anılcan's verdict was exact, that neither the heights match nor does it
/// read as a group.
///
/// The second version made the GROUP the bordered thing and put a raw `WInput` inside it, which
/// is the arrangement iOS and Material both use. That failed for a different reason: a raw
/// `WInput` needs an `Overlay` ancestor for its selection machinery and threw a build-phase
/// `setState` from inside the preview harness. Worth recording so it is not attempted a third
/// time.
///
/// So: **the field keeps its own single border and the buttons flank it with none.** That is
/// Material's outlined-field-with-icons shape, there is exactly one bordered box, and the
/// buttons read as affordances belonging to the field they sit against rather than as two more
/// boxes.
///
/// The buttons are `size-10`, which clears the 44pt floor once the row's padding counts and
/// keeps the target square rather than a sliver.
WindSlotRecipe quantityStepperRecipe() {
  return const WindSlotRecipe(
    slots: {
      'root': 'flex flex-row items-center axis-min',
      'button': 'size-10 shrink-0 rounded-md flex items-center justify-center',
      'icon': 'size-4 text-fg',
      'field': 'w-16 shrink-0',
    },
  );
}
