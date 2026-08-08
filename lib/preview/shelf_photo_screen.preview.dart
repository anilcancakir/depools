import 'package:flutter/widgets.dart';

import '../resources/views/products/shelf_photo_view.dart';
import 'preview_mock_harness.dart';
import 'responsive_screen_preview.dart';

/// Feature-screen preview: a shelf photograph read and waiting for review.
///
/// **The photograph stays on screen with numbered boxes and every row carries its number**
/// (D60). `ai-enrichment.md` sketches a film strip of candidate crops; the photograph IS the
/// strip, so drawing boxes on it and numbering the rows to match gives the spatial link without
/// a second set of images, and it works with no hover state, which a static review and a screen
/// reader both need.
///
/// Six regions, four products. Region 3 is a bottle nothing could name, which the doc requires
/// be presented rather than invented, and region 6 is a shelf label the recogniser took for a
/// product. The accept button counts the four, not the six: a button reading "6 ürünü ekle"
/// would promise to write an unnamed bottle and a price tag.
///
/// The credit line is there because `ai-enrichment.md` says it is worth telling users: one photo
/// is one credit however many products it yields, which makes this the cheapest capture path in
/// the app and nothing in the interface would otherwise say so.
class ShelfPhotoScreenPreview extends StatelessWidget {
  /// Creates the shelf photo preview.
  const ShelfPhotoScreenPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const ResponsiveScreenPreview(state: PreviewState.success, builder: _build);
  }

  static Widget _build(BuildContext context) => const ShelfPhotoView();
}
