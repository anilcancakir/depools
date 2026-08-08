import 'package:flutter/widgets.dart';

import '../resources/views/products/product_draft_view.dart';
import 'preview_mock_harness.dart';
import 'responsive_screen_preview.dart';

/// Feature-screen preview: a product being created, MID-ENRICHMENT.
///
/// The state nobody designs and everybody ships. For the first second or two after the
/// user types a name, most of this card is skeletons, and if that moment is ugly or
/// ambiguous it is the moment every single product creation passes through.
class ProductDraftScreenPreview extends StatelessWidget {
  /// Creates the mid-enrichment draft preview.
  const ProductDraftScreenPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const ResponsiveScreenPreview(state: PreviewState.success, builder: _build);
  }

  static Widget _build(BuildContext context) => const ProductDraftView();
}
