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
      'image': 'w-full h-full object-cover',
      // Centred on the neutral fill. `font-semibold` so a single letter still reads as deliberate at
      // this size rather than as leftover text.
      'initial': 'font-semibold text-fg-muted',
    },
    variants: {
      'size': {
        // A list row: large enough to recognise a familiar package, small enough that the row stays a
        // row. Matches the 40pt leading element iOS lists use.
        'sm': {'root': 'size-10', 'initial': 'text-sm'},
        // A card or a sheet, where the picture is part of what the user is checking rather than a hint.
        'md': {'root': 'size-16', 'initial': 'text-lg'},
      },
    },
    defaultVariants: {'size': 'sm'},
  );
}
