import 'package:flutter/widgets.dart';

import '../resources/views/products/receipt_review_view.dart';
import 'preview_mock_harness.dart';
import 'responsive_screen_preview.dart';

/// Feature-screen preview: reviewing a photographed receipt.
///
/// Rendered against a receipt WORSE than the acceptance criterion: 13 lines with four
/// unresolved, where the target is fewer than three edits. Designing against the
/// flattering case is how a review screen ends up unusable on a bad receipt, which is the
/// one the user will remember.
///
/// Thirteen rather than the doc's 15-to-25 range on purpose: the fixture is long enough
/// to show the grouping and short enough to read in one screenshot. The proportion is
/// what is being reviewed, not the row count.
class ReceiptReviewScreenPreview extends StatelessWidget {
  /// Creates the receipt review preview.
  const ReceiptReviewScreenPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const ResponsiveScreenPreview(state: PreviewState.success, builder: _build);
  }

  static Widget _build(BuildContext context) => const ReceiptReviewView();
}
