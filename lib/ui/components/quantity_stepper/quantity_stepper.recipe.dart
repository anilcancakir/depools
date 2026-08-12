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
      // Wide enough for a number AND its unit, because the unit now lives inside it. Measured at
      // `w-16` (64px), which is what it was when the unit floated outside: "piece" filled the field
      // and pushed the 12 out of sight entirely, and the placeholder dash rendered on top of the unit
      // so the empty state read as struck-through text.
      'field': 'w-24 shrink-0',
      // Its own border and radius removed so the group's are the only ones, and the same fill
      // as the group so the surface is continuous.
      // `focus:ring-1` halves the ring `MSInput`'s own recipe applies (`focus:ring-2`), which read as
      // a thick slab on web and, on a segment inside a shared border, fought the control's outline
      // rather than pointing at a field. Thinner, not absent: a focus indicator is required (WCAG
      // 2.4.7) and it keeps the primary colour so it is still unmistakably the focused one.
      //
      // The caller's className is emitted LAST, so this overrides the component's own variant at the
      // same granularity rather than having to disable it.
      'input': 'border-0 rounded-none bg-surface-container text-center focus:ring-1',
      // The opened-unit segment, INSIDE the same border with a hairline before it.
      //
      // **Two separately bordered boxes read as two independent quantities**, and on a product whose
      // base unit equals its content unit both labels said the same word, so nothing on screen said
      // which was which. This is one quantity in two parts, so it is one control in two segments and
      // the divider is the only thing between them.
      //
      // Wider than the whole field because a remainder is a measured amount: `500` and `1.240` both
      // have to fit where the whole count is usually one or two digits.
      'remainder': 'w-28 shrink-0 border-l border-color-border',
      // The unit, in the field it belongs to rather than floating beside the control. A unit on the
      // outside is a separate object; inside, it is part of the number it measures.
      'unit': 'text-xs text-fg-muted pr-2',
    },
  );
}
