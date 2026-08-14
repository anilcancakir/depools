import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import 'product_thumb.dart';

/// Static variant-matrix preview for [ProductThumb].
///
/// Both sizes across the three states a real list holds: a picture, no picture, and a url that will not
/// load. The third is not hypothetical, which is why it is previewed rather than described: two of the
/// three sources are urls on somebody else's server, and an Open Food Facts photograph is deliberately
/// not copied to our disk.
///
/// **Two things to check here.** Every box in a row must be the same size whether or not it holds a
/// picture, because that is the entire reason this component exists. And the failing url must settle on
/// the same letter as the empty one rather than on a broken-image glyph: a product whose photograph is
/// unreachable is not a product in an error state.
class ProductThumbPreview extends StatelessWidget {
  /// Creates the ProductThumb preview.
  const ProductThumbPreview({super.key});

  // demo-data-start: product names standing in for a tenant's own catalogue
  static const String _named = 'Pınar Süt Tam Yağlı 1 lt';
  static const String _other = 'Zeytinyağı';
  // demo-data-end

  /// The product the photograph below actually shows.
  ///
  /// Named separately rather than reusing `_named`, because a picture of a jar of hazelnut spread
  /// under the word `Süt` makes the one state this preview exists to check unreadable: a reviewer
  /// cannot tell a wrong image from a wrong fixture. Turkish barcodes are thin on Open Food Facts,
  /// so the choice is a foreign name with its own photograph or a local name with none.
  // demo-data-start
  static const String _photographed = 'Nutella 400 g';
  // demo-data-end

  /// A real Open Food Facts url, so the loaded state is the one users get rather than a local asset.
  ///
  /// Checked rather than invented: the first version of this preview made a plausible-looking path up,
  /// it 404'd, and the box rendered blank while every other state looked right. That is also why the
  /// missing case below uses a 404 on the SAME host rather than an unresolvable one: a removed
  /// photograph is the realistic failure and a dead domain is not.
  static const String _url =
      'https://images.openfoodfacts.org/images/products/301/762/042/2003/front_en.879.200.jpg';

  /// A url on the real host that is not there.
  static const String _missing =
      'https://images.openfoodfacts.org/images/products/000/000/000/0000/front_en.1.200.jpg';

  @override
  Widget build(BuildContext context) {
    return const WDiv(
      className: 'flex flex-col gap-6 p-6',
      children: [
        WDiv(
          className: 'flex flex-col gap-3 p-4 rounded-lg bg-surface-container',
          children: [
            WText('sm, a list row', className: 'text-xs text-fg-muted'),
            WDiv(
              className: 'flex flex-row items-center gap-3',
              children: [
                ProductThumb(name: _photographed, imageUrl: _url),
                ProductThumb(name: _named),
                ProductThumb(name: _other),
                // Nothing knew this barcode yet, so the row has no name either.
                ProductThumb(name: ''),
                ProductThumb(name: _named, imageUrl: _missing),
                ProductThumb(name: _named, imageUrl: 'https://example.invalid/unresolvable.jpg'),
              ],
            ),
          ],
        ),
        WDiv(
          className: 'flex flex-col gap-3 p-4 rounded-lg bg-surface-container',
          children: [
            WText('md, a card or a sheet', className: 'text-xs text-fg-muted'),
            WDiv(
              className: 'flex flex-row items-center gap-3',
              children: [
                ProductThumb(name: _photographed, imageUrl: _url, size: ProductThumbSize.md),
                ProductThumb(name: _named, size: ProductThumbSize.md),
                ProductThumb(name: '', size: ProductThumbSize.md),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
