import 'package:flutter/widgets.dart';

import '../resources/views/products/shopping_list_view.dart';
import 'preview_mock_harness.dart';
import 'screen_preview_scaffold.dart';

/// Feature-screen preview: the shopping list mid-trip.
///
/// Read the reason column top to bottom. The claim changes SHAPE as the history thins out:
/// a number for the milk, a bucket for the bulgur, a bare ratio with no time in it for the
/// screwdriver set. That progression is D46, and it is the screen's answer to the question
/// `forecasting.md` left open about showing a probabilistic forecast to someone who does not
/// read forecasts.
///
/// Every quantity is derived from `productFixtures`, so a line here cannot contradict the
/// product screen for the same product. That guard exists because this app already shipped
/// a list and a detail page disagreeing about one product's total.
///
/// Two items are ticked, which is the state that makes the receipt action appear. The tick
/// means the trolley, not the shelf: nothing has entered stock, and the line above the
/// button says so.
class ShoppingListScreenPreview extends StatelessWidget {
  /// Creates the shopping list preview.
  const ShoppingListScreenPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const ScreenPreviewScaffold(state: PreviewState.success, builder: _build);
  }

  static Widget _build(BuildContext context) => const ShoppingListView();
}
