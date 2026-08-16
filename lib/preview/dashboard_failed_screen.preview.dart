import 'package:flutter/widgets.dart';

import '../resources/views/dashboard_fixtures.dart';
import '../resources/views/dashboard_view.dart';
import 'responsive_screen_preview.dart';

/// The overview with one section's source unavailable, at both widths.
///
/// This is the entry that makes the failure design reviewable: the dates card is replaced in place
/// and the four counters, the capture actions and the shortage list are still there. A full-screen
/// error state would have taken all of them.
@immutable
class DashboardFailedScreenPreview extends StatelessWidget {
  /// Creates the [DashboardFailedScreenPreview].
  const DashboardFailedScreenPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return ResponsiveScreenPreview(
      builder: (BuildContext context) => DashboardView.sectionFailed(summary: dashboardFixture()),
    );
  }
}
