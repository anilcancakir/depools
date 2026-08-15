import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../product_thumb/product_thumb.dart';
import 'product_gallery.recipe.dart';

/// One picture the gallery draws, reduced to what this component needs.
///
/// A record rather than the app's `ProductImage`, so `lib/ui/` keeps not importing `lib/resources/`:
/// a component that knew the payload model could not be previewed without one.
typedef GalleryPicture = ({String id, String url, String? attribution, bool isPrimary});

/// **ProductGallery**
///
/// A product's pictures, the primary marked, with one control to add another.
///
/// **The primary is marked with a glyph and not only with a tint**, which `design.md` asks of any
/// selection: a fill alone is subtle in light mode and says nothing at all to a colour-blind reader.
///
/// **Every picture is tappable and none of them acts on the tap.** Promoting and removing are two
/// actions on one small square, and a long-press is not discoverable on the web build this app also
/// ships, so a tap opens the caller's own menu instead. That keeps the component free of the sheet
/// and the copy it would carry.
///
/// The row WRAPS rather than scrolls. The server caps a gallery at eight pictures, so the whole set
/// fits two rows even on a phone, and a horizontal scroller would hide items behind a gesture with
/// no affordance.
@immutable
class ProductGallery extends StatelessWidget {
  static const IconData _primaryIcon = Icons.check;
  static const IconData _addIcon = Icons.add_a_photo_outlined;

  /// The pictures, in the order they should read. The caller sorts; this draws.
  final List<GalleryPicture> pictures;

  /// The product's name, which supplies each thumbnail's fallback initial.
  final String name;

  /// Called with a picture's id when it is tapped.
  final ValueChanged<String>? onSelect;

  /// Called when the add control is tapped. Null hides it, which is what a full gallery does.
  final VoidCallback? onAdd;

  /// The already-localised label for the add control, for a screen reader.
  final String addLabel;

  /// Builds the already-localised label for one picture, given its position and whether it leads.
  final String Function(int index, bool isPrimary)? pictureLabel;

  /// Extra classes from the caller, appended last.
  final String? className;

  /// Creates a [ProductGallery].
  const ProductGallery({
    super.key,
    required this.pictures,
    required this.name,
    required this.addLabel,
    this.onSelect,
    this.onAdd,
    this.pictureLabel,
    this.className,
  });

  /// The credits to print under the row, each said once however many pictures carry it.
  ///
  /// A linked photograph is shown under a licence that asks for the credit to be VISIBLE, and two
  /// pictures from the same source do not need saying twice.
  List<String> get _credits {
    final Set<String> seen = <String>{};

    for (final GalleryPicture picture in pictures) {
      final String? credit = picture.attribution?.trim();

      if (credit != null && credit.isNotEmpty) seen.add(credit);
    }

    return seen.toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final slots = productGalleryRecipe()(
      classNames: className == null ? null : {'root': className!},
    );

    return WDiv(
      className: slots['root'],
      children: [
        _buildRow(slots),
        for (final String credit in _credits) WText(credit, className: slots['attribution']),
      ],
    );
  }

  /// The pictures and the add control, on one wrapping line.
  Widget _buildRow(Map<String, String> slots) {
    return WDiv(
      className: slots['row'],
      children: [
        for (final (int index, GalleryPicture picture) in pictures.indexed)
          WAnchor(
            onTap: onSelect == null ? null : () => onSelect!(picture.id),
            semanticLabel: pictureLabel?.call(index, picture.isPrimary),
            child: WDiv(
              className: slots['cell'],
              children: [
                ProductThumb(name: name, imageUrl: picture.url),
                if (picture.isPrimary)
                  WDiv(
                    className: slots['mark'],
                    child: WIcon(_primaryIcon, className: slots['markIcon']),
                  ),
              ],
            ),
          ),
        if (onAdd != null)
          WAnchor(
            onTap: onAdd,
            semanticLabel: addLabel,
            child: WDiv(
              className: slots['add'],
              child: WIcon(_addIcon, className: slots['addIcon']),
            ),
          ),
      ],
    );
  }
}
