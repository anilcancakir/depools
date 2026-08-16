import 'package:flutter/widgets.dart';

import '../resources/views/dashboard_fixtures.dart';
import '../resources/views/dashboard_view.dart';
import 'preview_mock_harness.dart';
import 'responsive_screen_preview.dart';

/// Feature-screen preview: the app dashboard landing view, authenticated and
/// backend-free.
class DashboardScreenPreview extends StatelessWidget {
  /// Creates the dashboard screen preview.
  const DashboardScreenPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const ResponsiveScreenPreview(state: PreviewState.success, builder: _build);
  }

  static Widget _build(BuildContext context) => DashboardView(summary: dashboardFixture());
}
