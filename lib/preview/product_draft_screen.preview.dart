import 'package:flutter/widgets.dart';

import '../app/models/product_draft.dart';
import '../resources/views/products/product_draft_view.dart';
import 'preview_mock_harness.dart';
import 'responsive_screen_preview.dart';

/// Feature-screen preview: a product being created, MID-ENRICHMENT.
///
/// The state nobody designs and everybody ships. For the first second or two after the
/// user takes the photograph, most of this card is skeletons, and if that moment is ugly
/// or ambiguous it is the moment every single product creation passes through.
///
/// The draft is passed in rather than read from the controller, which is the same contract the
/// route uses filled from a different source: `ProductDraft` is the type the endpoint returns, so
/// this cannot drift from the API the way a hand-built fixture would, and the catalog stays offline.
class ProductDraftScreenPreview extends StatelessWidget {
  /// Creates the mid-enrichment draft preview.
  const ProductDraftScreenPreview({super.key});

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
    // Empty on purpose: mid-read is exactly the moment nothing has arrived yet.
    ProductDraft(imagePhash: ''),
    isEnriching: true,
  );
}
