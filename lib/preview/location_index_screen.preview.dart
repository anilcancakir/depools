import 'package:flutter/widgets.dart';

import '../resources/views/locations/location_index_view.dart';
import 'preview_mock_harness.dart';
import 'responsive_screen_preview.dart';

/// Feature-screen preview: the location hierarchy.
///
/// The tree nothing in the app showed until now, even though the product detail, the
/// filter and the stock-in suggestion all assumed it.
class LocationIndexScreenPreview extends StatelessWidget {
  /// Creates the location index preview.
  const LocationIndexScreenPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const ResponsiveScreenPreview(state: PreviewState.success, builder: _build);
  }

  static Widget _build(BuildContext context) => const LocationIndexView();
}
