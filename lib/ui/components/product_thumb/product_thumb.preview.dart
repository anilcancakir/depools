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

  /// A real Open Food Facts url, so the loaded state is the one users get rather than a local asset.
  static const String _url = 'https://images.openfoodfacts.org/images/products/869/050/400/4073/front_en.4.400.jpg';

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
                ProductThumb(name: _named, imageUrl: _url),
                ProductThumb(name: _named),
                ProductThumb(name: _other),
                // Nothing knew this barcode yet, so the row has no name either.
                ProductThumb(name: ''),
                ProductThumb(name: _named, imageUrl: 'https://example.invalid/missing.jpg'),
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
                ProductThumb(name: _named, imageUrl: _url, size: ProductThumbSize.md),
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
