import 'package:flutter/widgets.dart';

import '../resources/views/products/product_index_view.dart';
import 'preview_mock_harness.dart';
import 'screen_preview_scaffold.dart';

/// Feature-screen preview: Stock list with products.
class ProductIndexScreenPreview extends StatelessWidget {
  /// Creates the ProductIndexScreen preview.
  const ProductIndexScreenPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const ScreenPreviewScaffold(state: PreviewState.success, builder: _build);
  }

  static Widget _build(BuildContext context) => const ProductIndexView();
}
