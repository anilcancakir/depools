import 'package:flutter/widgets.dart';

import '../resources/views/products/product_show_view.dart';
import 'preview_mock_harness.dart';
import 'responsive_screen_preview.dart';

/// Feature-screen preview: product detail for a SERIAL-tracked product.
///
/// Its own catalog entry rather than a toggle on the lot-tracked one, because D28's
/// second unit model only appears on this path and a variant reachable only by editing
/// a fixture is a variant nobody reviews. Half of what serial tracking changes is
/// visual: the lot list becomes a serial list, the quantity column disappears from
/// those rows, and the date on them is a warranty rather than an expiry.
class ProductShowSerialScreenPreview extends StatelessWidget {
  /// Creates the serial-tracked product show screen preview.
  const ProductShowSerialScreenPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const ResponsiveScreenPreview(state: PreviewState.success, builder: _build);
  }

  static Widget _build(BuildContext context) => const ProductShowView.serialTracked();
}
