import 'package:flutter/widgets.dart';

import '../resources/views/products/count_fixtures.dart';
import '../resources/views/products/stock_take_view.dart';
import 'preview_mock_harness.dart';
import 'responsive_screen_preview.dart';

/// Feature-screen preview: a part-finished count of the fridge.
///
/// Three states at once, which is the whole design. The milk has been counted and disagrees,
/// the cheese has been counted and agrees, and the yoghurt has not been counted at all.
///
/// The two things to read. **No expected figure appears next to the uncounted row** (D58):
/// blind while counting, because a counter shown "5" looks at a shelf and sees five, and
/// informed the moment a number is entered. And **the milk is counted in two fields**, because
/// it holds a sealed carton plus an opened half-litre and "1,5 adet" is not something anybody
/// can verify against a shelf.
///
/// The summary states what the commit will NOT do, which is the part a user would not think to
/// ask about: a skipped row stays exactly as it was, and a count that agreed writes no movement
/// at all.
class StockTakeScreenPreview extends StatelessWidget {
  /// Creates the stock-take preview.
  const StockTakeScreenPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const ResponsiveScreenPreview(state: PreviewState.success, builder: _build);
  }

  /// The fixture lines are passed in rather than read from a controller, which is what keeps the
  /// catalog renderable with no backend and no authenticated tenant behind it. The wired screen
  /// takes the same shape from `ProductController` instead.
  static Widget _build(BuildContext context) => StockTakeView(lines: fridgeCount);
}
