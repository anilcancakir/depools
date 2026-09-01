import 'package:flutter/widgets.dart';

import '../app/models/product_draft.dart';
import '../resources/views/products/product_draft_view.dart';
import 'preview_mock_harness.dart';
import 'responsive_screen_preview.dart';

/// Feature-screen preview: the same draft after the read has settled.
///
/// The state the user actually acts on. Brand, description, category and unit arrived from the
/// photograph and carry their marks; SKU is empty because no model can know a tenant's own code, and
/// that is its resting state rather than a transient one.
class ProductDraftSettledScreenPreview extends StatelessWidget {
  /// Creates the settled draft preview.
  const ProductDraftSettledScreenPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const ResponsiveScreenPreview(
      state: PreviewState.success,
      builder: _build,
      // Bounded so the phone frame is reachable in one screenshot: the wide frame grows
      // with its content otherwise, and 390px is the width this card actually has to
      // survive.
      bounded: true,
    );
  }

  static Widget _build(BuildContext context) => const ProductDraftView.preview(
    ProductDraft(
      imagePhash: '0000000000000000c3a5f0e1d2b47896',
      recognised: true,
      outcome: 'succeeded',
      name: 'Süt Tam Yağlı 1 L',
      brand: 'Pınar',
      description: 'Tam yağlı UHT süt, 1 litre karton.',
      categoryLabel: 'Milk',
      unit: 'C62',
      // Everything the read produced, so the marks render: the unit is the one this screen shows a
      // mark on, because a wrongly inferred unit changes what every quantity in the ledger means.
      inferred: <String>{'name', 'brand', 'description', 'category', 'unit'},
    ),
  );
}
