import 'package:flutter/widgets.dart';

import '../resources/views/products/product_fixtures.dart';
import '../resources/views/products/product_show_view.dart';
import 'preview_mock_harness.dart';
import 'responsive_screen_preview.dart';

/// Feature-screen preview: product detail, backend-free.
///
/// Rendered against the hard case on purpose. See [ProductShowView] for what that
/// means and why the easy case would not have been worth designing.
class ProductShowScreenPreview extends StatelessWidget {
  /// Creates the product show screen preview.
  const ProductShowScreenPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const ResponsiveScreenPreview(state: PreviewState.success, builder: _build);
  }

  static Widget _build(BuildContext context) => ProductShowView(item: productFixtures.firstWhere((p) => p.tracking == TrackingMode.lot));
}
