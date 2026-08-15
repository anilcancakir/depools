import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import 'product_gallery.dart';

/// Static preview for [ProductGallery].
///
/// The four states a real product moves through, in the order it moves through them: nothing yet,
/// one picture (which is automatically the primary), several with one leading, and a linked
/// photograph whose credit has to be visible.
///
/// **Two things to check here.** The primary's mark has to be legible over the picture it sits on,
/// which is why the loaded cell uses a real photograph rather than a fallback letter, and the add
/// control has to be the same size as a thumbnail so the row keeps one rhythm.
class ProductGalleryPreview extends StatelessWidget {
  /// Creates the ProductGallery preview.
  const ProductGalleryPreview({super.key});

  /// A checked Open Food Facts url, so the loaded state is the one users get.
  ///
  /// The same one `ProductThumb`'s preview uses, and for the reason recorded there: the first
  /// version of that preview invented a plausible path, it 404'd, and the box rendered its fallback
  /// letter while claiming to preview a photograph.
  static const String _url =
      'https://images.openfoodfacts.org/images/products/301/762/042/2003/front_en.879.200.jpg';

  // demo-data-start: a product name and a credit standing in for a tenant's own
  static const String _name = 'Nutella 400 g';
  static const String _credit = 'Open Food Facts contributors, CC-BY-SA 3.0';
  // demo-data-end

  static void _noop() {}

  static void _select(String id) {}

  static String _label(int index, bool isPrimary) => 'Picture ${index + 1}';

  @override
  Widget build(BuildContext context) {
    return WDiv(
      className: 'flex flex-col gap-6 p-6',
      children: [
        _group('empty, so only the add control', const <GalleryPicture>[]),
        _group('one picture, which leads by definition', const <GalleryPicture>[
          (id: 'a', url: _url, attribution: null, isPrimary: true),
        ]),
        _group('several, one of them leading', const <GalleryPicture>[
          (id: 'a', url: _url, attribution: null, isPrimary: true),
          (id: 'b', url: '', attribution: null, isPrimary: false),
          (id: 'c', url: '', attribution: null, isPrimary: false),
        ]),
        _group('a linked photograph, whose credit has to be visible', const <GalleryPicture>[
          (id: 'a', url: _url, attribution: _credit, isPrimary: true),
          (id: 'b', url: _url, attribution: _credit, isPrimary: false),
        ]),
      ],
    );
  }

  Widget _group(String caption, List<GalleryPicture> pictures) {
    return WDiv(
      className: 'flex flex-col gap-3 p-4 rounded-lg bg-surface-container',
      children: [
        WText(caption, className: 'text-xs text-fg-muted'),
        ProductGallery(
          pictures: pictures,
          name: _name,
          addLabel: 'Add a picture',
          onSelect: _select,
          onAdd: _noop,
          pictureLabel: _label,
        ),
      ],
    );
  }
}
