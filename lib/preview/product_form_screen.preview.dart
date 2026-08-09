import 'package:flutter/widgets.dart';

import '../resources/views/products/product_form_view.dart';
import 'responsive_screen_preview.dart';

/// The manual product form, at both widths.
///
/// The state worth reviewing here is the EMPTY one, because that is what the user meets: the
/// primary action is disabled until a name exists, and `inventory-core.md`'s 60-second criterion
/// is about how little stands between an empty form and stock on a shelf.
@immutable
class ProductFormScreenPreview extends StatelessWidget {
  /// Creates the [ProductFormScreenPreview].
  const ProductFormScreenPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return ResponsiveScreenPreview(builder: (BuildContext context) => const ProductFormView());
  }
}
