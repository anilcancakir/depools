import 'package:flutter/widgets.dart';

import '../resources/views/products/running_low_view.dart';
import 'preview_mock_harness.dart';
import 'responsive_screen_preview.dart';

/// Feature-screen preview: nothing short.
///
/// The good outcome, and the copy has to carry one awkward truth: a product with no target
/// level can never appear on this screen however low it gets. Someone looking at an empty
/// list with a half-empty pantry deserves to be told that rather than left to conclude the
/// feature is broken.
class RunningLowEmptyScreenPreview extends StatelessWidget {
  /// Creates the empty running-low preview.
  const RunningLowEmptyScreenPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const ResponsiveScreenPreview(state: PreviewState.success, builder: _build);
  }

  static Widget _build(BuildContext context) => const RunningLowView.empty();
}
