import 'package:flutter/widgets.dart';

import '../resources/views/locations/location_index_view.dart';
import 'preview_mock_harness.dart';
import 'responsive_screen_preview.dart';

/// Feature-screen preview: the location tree, narrowed to empty places.
///
/// Its own entry because a FILTERED tree is a different layout, not a shorter one. The
/// matches lose their ancestors, so indent stops meaning anything and each row falls back
/// to its full path. That is the one place `LocationRow`'s own-name rule gives way, and a
/// variant only reachable by tapping a segment is a variant nobody screenshots.
class LocationIndexFilteredScreenPreview extends StatelessWidget {
  /// Creates the filtered location index preview.
  const LocationIndexFilteredScreenPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const ResponsiveScreenPreview(state: PreviewState.success, builder: _build);
  }

  static Widget _build(BuildContext context) => const LocationIndexView.filtered();
}
