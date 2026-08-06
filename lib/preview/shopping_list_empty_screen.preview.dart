import 'package:flutter/widgets.dart';

import '../resources/views/products/shopping_list_view.dart';
import 'preview_mock_harness.dart';
import 'screen_preview_scaffold.dart';

/// Feature-screen preview: nothing to buy.
///
/// **The good outcome, and it must not read as a failure.** An empty shopping list means
/// nothing is running out, which is the result the whole forecasting feature exists to
/// produce. So the copy states the mechanism rather than apologising for a blank, and the
/// receipt action is gone because there is nothing in a trolley to reconcile.
class ShoppingListEmptyScreenPreview extends StatelessWidget {
  /// Creates the empty shopping list preview.
  const ShoppingListEmptyScreenPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const ScreenPreviewScaffold(state: PreviewState.success, builder: _build);
  }

  static Widget _build(BuildContext context) => const ShoppingListView.empty();
}
