import 'package:magic/magic.dart';

/// Builds the [WindSlotRecipe] for the IconPicker component.
///
/// **The grid is a fixed 44pt tile, not a flexible one.** Every tile holds one glyph and nothing
/// else, so there is no content to size it by, and 44 is the hit target `DESIGN.md` requires of
/// anything interactive. A row of them wraps rather than scrolling sideways: the count is variable
/// by definition and a horizontal scroller hides options behind a gesture nothing advertises.
///
/// The selected tile takes the app's own selection tone (`bg-primary-container`) rather than a
/// heavier border, because that is what every other chip and option in this app uses and selection
/// should read the same way wherever it appears.
WindSlotRecipe iconPickerRecipe() {
  return const WindSlotRecipe(
    slots: {
      'root': 'flex flex-col gap-3 w-full',
      'grid': 'flex flex-row wrap items-center gap-2',
      // Card tone plus a hairline for the unselected state. NOT
      // `bg-surface-container-high`: that is DESIGN.md's INPUT background and reads as recessed in
      // light mode, which is the universal look of a disabled control.
      'tile': 'size-11 rounded-md flex items-center justify-center bg-surface-container border border-color-border',
      'glyph': 'size-5 text-fg',
      'status': 'text-sm text-fg-muted',
    },
    variants: {
      'state': {
        'idle': {},
        // The chosen tile, in the tone selection carries everywhere else in this app.
        'selected': {
          'tile': 'size-11 rounded-md flex items-center justify-center bg-primary-container border border-color-border',
        },
      },
    },
    defaultVariants: {'state': 'idle'},
  );
}
