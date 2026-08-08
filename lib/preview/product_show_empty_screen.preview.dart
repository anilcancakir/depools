import 'package:flutter/widgets.dart';

import '../resources/views/products/product_show_view.dart';
import 'preview_mock_harness.dart';
import 'responsive_screen_preview.dart';

/// Feature-screen preview: product detail for a product with no stock yet.
///
/// The first-run state, and the one a new user actually sees first: a product exists
/// as soon as a scan or a receipt line creates it, and the first movement can come
/// minutes or days later. Empty here is normal, not an error, which is why the three
/// collection cards carry designed empty states with a next step rather than rendering
/// as blank panels.
class ProductShowEmptyScreenPreview extends StatelessWidget {
  /// Creates the empty product show screen preview.
  const ProductShowEmptyScreenPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const ResponsiveScreenPreview(state: PreviewState.success, builder: _build);
  }

  static Widget _build(BuildContext context) => const ProductShowView.newProduct();
}
