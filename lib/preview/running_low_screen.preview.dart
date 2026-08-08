import 'package:flutter/widgets.dart';

import '../resources/views/products/running_low_view.dart';
import 'preview_mock_harness.dart';
import 'responsive_screen_preview.dart';

/// Feature-screen preview: what is short, and how sure the app is about it.
///
/// The four groups are the point. Two products are simply gone, one has enough history for a
/// real days-of-cover figure, two have some history and get no number at all, and one has
/// only a target. `forecasting.md` gates hard on that: below roughly ten movements there is
/// no forecast, and rather than hide the gate this screen makes it the structure and says in
/// one line what each group may claim.
///
/// Days of cover appears in exactly one group, because that is the only tier where the number
/// exists. It is not an editorial omission elsewhere.
///
/// `test/running_low_test.dart` asserts that every product here is also on the shopping list
/// and that the list is a strict superset. Two screens describing the same shortage from
/// different angles is exactly where a contradiction would be most visible.
class RunningLowScreenPreview extends StatelessWidget {
  /// Creates the running-low preview.
  const RunningLowScreenPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const ResponsiveScreenPreview(state: PreviewState.success, builder: _build);
  }

  static Widget _build(BuildContext context) => const RunningLowView();
}
