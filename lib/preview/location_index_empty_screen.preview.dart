import 'package:flutter/widgets.dart';

import '../resources/views/locations/location_index_view.dart';
import 'preview_mock_harness.dart';
import 'responsive_screen_preview.dart';

/// Feature-screen preview: no locations yet.
///
/// Its own entry because this is a BLOCKER rather than a decorative empty state: a tenant
/// with no locations cannot receive stock anywhere, so it is the first screen of every
/// account and it has to offer a way out.
class LocationIndexEmptyScreenPreview extends StatelessWidget {
  /// Creates the empty location index preview.
  const LocationIndexEmptyScreenPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const ResponsiveScreenPreview(state: PreviewState.success, builder: _build);
  }

  static Widget _build(BuildContext context) => const LocationIndexView.empty();
}
