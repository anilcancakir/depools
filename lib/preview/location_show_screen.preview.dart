import 'package:flutter/widgets.dart';

import '../resources/views/locations/location_fixtures.dart';
import '../resources/views/products/product_fixtures.dart';
import '../resources/views/locations/location_show_view.dart';
import 'responsive_screen_preview.dart';

/// One location's contents, at both widths.
///
/// The populated case, which is where the screen's one real decision shows: what is held HERE and
/// what is in the locations inside it are two sections, not one list.
@immutable
class LocationShowScreenPreview extends StatelessWidget {
  /// Creates the [LocationShowScreenPreview].
  const LocationShowScreenPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return ResponsiveScreenPreview(builder: (BuildContext context) => LocationShowView.preview(
        nodes: locationTree,
        held: productFixtures
            .where((ProductListItem p) => p.locationSummary == 'Kiler \u203a Raf 1')
            .toList(),
      ));
  }
}
