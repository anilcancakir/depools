import 'package:flutter/widgets.dart';

import '../resources/views/dashboard_view.dart';
import 'preview_mock_harness.dart';
import 'screen_preview_scaffold.dart';

/// Feature-screen preview: the app dashboard landing view, authenticated and
/// backend-free.
class DashboardScreenPreview extends StatelessWidget {
  /// Creates the dashboard screen preview.
  const DashboardScreenPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const ScreenPreviewScaffold(
      state: PreviewState.success,
      builder: _build,
    );
  }

  static Widget _build(BuildContext context) => const DashboardView();
}
