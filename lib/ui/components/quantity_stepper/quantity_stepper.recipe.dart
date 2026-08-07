import 'package:magic/magic.dart';

/// Builds the [WindSlotRecipe] for the QuantityStepper component.
///
/// **One border around the whole control, with the parts inside it.** The group owns the
/// border, the radius and the clipping; the two buttons and the field fill it and hairline
/// dividers separate them. That is how iOS and Material both draw a stepper, and it is the only
/// arrangement where the three parts read as one thing.
///
/// Two earlier shapes are recorded so they are not tried again:
///
/// 1. **Three separately bordered boxes in a row with gaps.** Three heights, two radii, nothing
///    tying them together. Anılcan: neither the heights match nor does it look like a group.
/// 2. **The group bordered, with a raw `WInput` inside.** Right shape, wrong widget: `WInput`
///    needs an `Overlay` ancestor for its selection machinery and threw a build-phase
///    `setState` from the preview harness.
///
/// The third shape (one bordered field, borderless buttons outside it) worked but was still two
/// visual objects rather than one control, which is what this replaces.
///
/// This one keeps `MSInput` and neutralises its own border and radius from the caller
/// (`border-0 rounded-none`), which is available because wind ships a `0` border width and a
/// `none` radius. The input takes the group's own fill so there is one continuous surface.
///
/// Card tone plus a hairline, like every interactive surface here: the input tone is darker than
/// a white card and reads as disabled.
WindSlotRecipe quantityStepperRecipe() {
  return const WindSlotRecipe(
    slots: {
      'root':
          'flex flex-row items-center axis-min rounded-md overflow-hidden '
          'bg-surface-container border border-color-border',
      'left': 'h-10 w-10 shrink-0 flex items-center justify-center border-r border-color-border',
      'right': 'h-10 w-10 shrink-0 flex items-center justify-center border-l border-color-border',
      'icon': 'size-4 text-fg',
      'field': 'w-16 shrink-0',
      // Its own border and radius removed so the group's are the only ones, and the same fill
      // as the group so the surface is continuous.
      'input': 'border-0 rounded-none bg-surface-container text-center',
    },
  );
}
