import 'package:flutter/widgets.dart';

import '../resources/views/products/product_draft_view.dart';
import 'preview_mock_harness.dart';
import 'screen_preview_scaffold.dart';

/// Feature-screen preview: a product being created, AFTER enrichment settles.
///
/// Its own entry rather than a toggle, because the two states have to be reviewable side
/// by side. This one shows the resting shape: values filled and marked `tahmin` where
/// they were inferred, and SKU still empty because no model can know a tenant's own code.
///
/// The pairing is deliberate. A skeleton that never resolves and a prompt that looks
/// like a value are both invisible in a single screenshot and obvious across two.
class ProductDraftSettledScreenPreview extends StatelessWidget {
  /// Creates the settled draft preview.
  const ProductDraftSettledScreenPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const ScreenPreviewScaffold(state: PreviewState.success, builder: _build);
  }

  static Widget _build(BuildContext context) => const ProductDraftView.settled();
}
