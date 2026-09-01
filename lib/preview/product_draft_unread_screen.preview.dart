import 'package:flutter/widgets.dart';

import '../app/models/product_draft.dart';
import '../resources/views/products/product_draft_view.dart';
import 'preview_mock_harness.dart';
import 'responsive_screen_preview.dart';

/// Feature-screen preview: the read came back with nothing, because the credits ran out.
///
/// **Its own preview because it is its own state, not an empty version of the settled one.**
/// `ai-enrichment.md` lists "credits exhausted" and "nothing recognisable" as separate error states
/// and requires manual creation to stay fully functional through both, so what has to be reviewable
/// is that the card is still editable and the line above it says which of the two happened.
///
/// The receipt slice shipped a screen that could not tell those apart, and it took driving the real
/// thing to find, because both were a 200 with an empty result.
class ProductDraftUnreadScreenPreview extends StatelessWidget {
  /// Creates the failed-read draft preview.
  const ProductDraftUnreadScreenPreview({super.key});

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
      recognised: false,
      outcome: 'no_credit',
    ),
  );
}
