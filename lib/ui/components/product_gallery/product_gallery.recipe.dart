import 'package:magic/magic.dart';

/// Builds the [WindSlotRecipe] for the ProductGallery component.
///
/// A row of thumbnails with the add control at the end, wrapping rather than scrolling: the ceiling
/// is eight pictures (`ProductImage::MAX_PER_PRODUCT`), so the whole gallery fits two rows even on a
/// phone, and a horizontal scroller would hide items behind a gesture with no affordance.
WindSlotRecipe productGalleryRecipe() {
  return const WindSlotRecipe(
    slots: {
      // A COLUMN holding the picture row and the credits, rather than one wrapping row holding both.
      // `w-full` on the credit inside a wrapping row did not push it onto its own line: it took the
      // remaining width and sat beside the add control, which reads fine at catalogue width and
      // would squeeze a long credit against a 40pt button on a phone. Two boxes cannot do that.
      'root': 'flex flex-col gap-2',
      // `wrap`, because the count is variable by definition and no width is known to fit it. This is
      // the anti-pattern `design.md` names for a badge row and it applies here for the same reason.
      'row': 'flex flex-row wrap items-center gap-2',
      // Each picture sits in a `relative` box so the primary's mark can be positioned on it. The
      // flex alignment lives on the MARK rather than here: wind turns a container with a positioned
      // child into a Stack, and a Stack ignores `items-center`, which is the trap `design.md`
      // records. Nothing here needs centring, so the two never collide.
      'cell': 'relative',
      // **The primary is marked with a glyph, not only with a tint.** `design.md`: selection carried
      // by fill alone is subtle in light mode and invisible to a colour-blind reader. The badge sits
      // on the corner of the picture it belongs to, over its own filled disc so it reads against a
      // photograph of any brightness.
      'mark': 'absolute -top-1 -right-1 size-5 rounded-full bg-primary flex items-center justify-center',
      'markIcon': 'size-3 text-on-primary',
      // The add control matches a `sm` thumbnail exactly, so the row keeps one rhythm whether it
      // holds one picture or eight. A dashed edge would need a border style wind does not carry, so
      // the distinction is the tone plus the glyph.
      'add': 'size-10 rounded-md bg-surface-container-high border border-color-border '
          'flex items-center justify-center',
      'addIcon': 'size-5 text-fg-muted',
      // Said once under the row rather than per picture: a credit repeated eight times is noise, and
      // the licence asks for it to be visible rather than adjacent.
      'attribution': 'text-xs text-fg-muted',
    },
  );
}
