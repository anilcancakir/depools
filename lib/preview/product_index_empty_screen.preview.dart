import 'package:flutter/widgets.dart';

import '../resources/views/products/product_index_view.dart';
import 'preview_mock_harness.dart';
import 'responsive_screen_preview.dart';

/// Feature-screen preview: Stock list for a tenant with no products yet.
class ProductIndexEmptyScreenPreview extends StatelessWidget {
  /// Creates the ProductIndexEmptyScreen preview.
  const ProductIndexEmptyScreenPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const ResponsiveScreenPreview(state: PreviewState.success, builder: _build);
  }

  static Widget _build(BuildContext context) => const ProductIndexView.empty();
}
