import 'package:magic/magic.dart';

/// Builds the [WindSlotRecipe] for the LabelPreview component.
///
/// **The page is white in both appearances, and that is not a token violation.** Every
/// other surface in this app flips with the theme, because it is a surface the user reads
/// on screen. This one is a picture OF PAPER: the sheet in the printer's tray is white at
/// two in the morning too, and a preview that renders it dark would be showing something
/// the printer cannot produce. So the page uses the fixed `paper` and `ink` aliases rather
/// than `surface` and `fg`.
///
/// That is also why criterion 7 ("preview matches print output") is a design constraint
/// and not a testing note: a preview that reflows, rescales or recolours cannot be checked
/// against a ruler, which is what criterion 1 asks a person to do.
///
/// An empty cell is drawn as a dashed-looking outline rather than left blank, because the
/// unused half of a sheet is the thing a user wants to see before committing paper. Wind
/// has no dashed-border token, so the outline is a hairline at low contrast: enough to
/// place the cell, not enough to compete with a real label.
WindSlotRecipe labelPreviewRecipe() {
  return const WindSlotRecipe(
    slots: {
      'root': 'flex flex-col gap-2 axis-min',
      // The page sits in a WELL, which is what every print preview in the world does: a
      // grey canvas with a white sheet on it. Without the tray, light mode put a #FFFFFF
      // page on a #FFFFFF card and the sheet dissolved into its container, separated by
      // one hairline. In dark mode the contrast had been doing that job for free, which is
      // exactly the kind of thing a dark-only review does not surface.
      //
      // `surface-container-high` is the input tone and this IS a well, so the semantics are
      // right here in a way they were not on the option rows.
      'tray': 'p-3 rounded-lg bg-surface-container-high',
      // `aspect-*` does not exist in wind, so the page's proportions come from an
      // AspectRatio inside; this only paints it.
      'page': 'bg-paper rounded-sm border border-color-border overflow-hidden',
      // Padding only, NO `flex flex-col`. The cell's child is a raw Column carrying
      // Expanded bands, and a Column nested inside wind's own Column would be handed
      // unbounded height: the outer one sizes to max and passes infinity to a non-flex
      // child, so every Expanded inside the inner one asserts "RenderBox was not laid
      // out". Wind does the paint, Flutter does the geometry, and the two must not both
      // claim the main axis.
      'cell': 'px-1',
      'emptyCell': 'flex flex-col items-stretch justify-center p-1',
      'emptyMark': 'flex-1 border border-color-ink-subtle rounded-sm',
      // A drawn text line rather than typeset text: at sheet scale, 9pt is six pixels.
      'textBar': 'w-full rounded-sm bg-ink-muted',
      'bar': 'bg-ink',
      'caption': 'text-xs text-fg-muted',
    },
  );
}
