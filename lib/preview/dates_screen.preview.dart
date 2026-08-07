import 'package:flutter/widgets.dart';

import '../resources/views/products/dates_view.dart';
import 'preview_mock_harness.dart';
import 'screen_preview_scaffold.dart';

/// Feature-screen preview: what is running out of time.
///
/// `forecasting.md` calls this the most immediately valuable of its three surfaces and the
/// one needing no forecast at all, and it had no screen until now.
///
/// The mix is the point. One cheese already off, an opened half-litre of milk with two days,
/// a sealed carton of the same milk with six, some bulgur, and a DRILL whose warranty ends in
/// two days. That last row is why the screen is not called "son kullanma": filtering
/// warranties out would be one more place the food assumption got baked in.
///
/// Two things to check. The horizon chips change the row count (3, 7 and 30 days give 4, 5
/// and 7 rows against this fixture), and the expired group never moves, because something
/// already off cannot be hidden by narrowing the window. And every row is a LOT: the same
/// milk appears twice, at two dates, in two places, which is the whole reason this is not a
/// product list.
class DatesScreenPreview extends StatelessWidget {
  /// Creates the dates preview.
  const DatesScreenPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const ScreenPreviewScaffold(state: PreviewState.success, builder: _build);
  }

  static Widget _build(BuildContext context) => const DatesView();
}
