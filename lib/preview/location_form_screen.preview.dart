import 'package:flutter/widgets.dart';

import '../resources/views/locations/location_form_view.dart';
import 'responsive_screen_preview.dart';

/// Creating a location, at both widths.
///
/// The state worth reviewing is the empty one: the parent chips, the depth counter in the section
/// header, and the path preview that says exactly what will be created.
@immutable
class LocationFormScreenPreview extends StatelessWidget {
  /// Creates the [LocationFormScreenPreview].
  const LocationFormScreenPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return ResponsiveScreenPreview(builder: (BuildContext context) => const LocationFormView());
  }
}
