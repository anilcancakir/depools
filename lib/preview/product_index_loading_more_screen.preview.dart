import 'package:flutter/widgets.dart';

import '../resources/views/products/product_index_view.dart';
import 'preview_mock_harness.dart';
import 'responsive_screen_preview.dart';

/// Feature-screen preview: the stock list with a page in flight.
///
/// Its own entry because a paginated list spends real time in this state on a slow
/// connection, and a footer that looks like the end of the data is how a user stops
/// scrolling with rows still unseen. Skeleton ROWS rather than a spinner, so the space the
/// incoming rows will occupy is already reserved and the list does not jump.
class ProductIndexLoadingMoreScreenPreview extends StatelessWidget {
  /// Creates the loading-more stock list preview.
  const ProductIndexLoadingMoreScreenPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const ResponsiveScreenPreview(state: PreviewState.success, builder: _build);
  }

  static Widget _build(BuildContext context) => const ProductIndexView.loadingMore();
}
