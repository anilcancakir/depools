import 'package:magic/magic.dart';

/// Builds the [WindSlotRecipe] for the ProductThumb component.
///
/// **The box is the same size whether or not there is a picture**, which is the whole reason this is a
/// component rather than a `WImage` at each call site. `design.md` names the failure directly: a
/// conditionally rendered leading element shifts the text beside it, and a list of rows is a table even
/// when it is built from flex boxes. Most products will have no image for a long time, so a gutter that
/// appears per row would make every list ragged.
///
/// The empty state is the product's initial on a neutral fill, which is the shape `magic_starter`
/// already uses for a user with no photo. A blank box would read as a failed image; a letter reads as an
/// identity.
///
/// Square with a small radius rather than the circle an avatar uses, because a product is a thing rather
/// than a person, and a photograph of a carton cropped to a circle loses its own edges.
WindSlotRecipe productThumbRecipe() {
  return const WindSlotRecipe(
    slots: {
      // `shrink-0`, because the row this sits in gives its body `flex-1 min-w-0`: without it a long
      // product name squeezes the picture rather than truncating itself.
      'root': 'shrink-0 rounded-md overflow-hidden bg-surface-container-high '
          'flex items-center justify-center',
      // **Sized explicitly per variant rather than `w-full h-full`, which did not resolve.** The root
      // centres its child so the letter sits in the middle, and inside a centring flex box a
      // percentage height has nothing to resolve against: the picture rendered at its intrinsic size
      // and spilled past the rounded corners, which `overflow-hidden` on the parent did not clip
      // either. Measured on screen with a real photograph, not reasoned about.
      'image': 'object-cover',
      // **The letter shown INSTEAD of a picture that did not load**, which needs its own box rather
      // than the image's: `errorBuilder`'s widget is laid out inside the image's sized slot at its
      // natural position, so the same `WText` that centres fine in an empty box sat in the top-left
      // corner of a failed one. Two boxes in one preview looked different for a reason that had
      // nothing to do with the state they were showing.
      'fallback': 'flex items-center justify-center font-semibold text-fg-muted',
      // Centred on the neutral fill. `font-semibold` so a single letter still reads as deliberate at
      // this size rather than as leftover text.
      'initial': 'font-semibold text-fg-muted',
    },
    variants: {
      'size': {
        // A list row: large enough to recognise a familiar package, small enough that the row stays a
        // row. Matches the 40pt leading element iOS lists use.
        'sm': {
          'root': 'size-10',
          'image': 'size-10',
          'fallback': 'size-10 text-sm',
          'initial': 'text-sm',
        },
        // A card or a sheet, where the picture is part of what the user is checking rather than a hint.
        'md': {
          'root': 'size-16',
          'image': 'size-16',
          'fallback': 'size-16 text-lg',
          'initial': 'text-lg',
        },
        // The detail screen's identity block. 80 rather than 64 because that is the size that screen
        // already drew before this component existed, and shrinking it would have been a design change
        // smuggled in as a refactor.
        'lg': {
          'root': 'size-20',
          'image': 'size-20',
          'fallback': 'size-20 text-2xl',
          'initial': 'text-2xl',
        },
      },
    },
    defaultVariants: {'size': 'sm'},
  );
}
