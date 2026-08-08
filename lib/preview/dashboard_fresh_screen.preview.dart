import 'package:flutter/widgets.dart';

import '../resources/views/dashboard_view.dart';
import 'preview_mock_harness.dart';
import 'responsive_screen_preview.dart';

/// Feature-screen preview: the dashboard for a tenant that has added nothing yet.
///
/// **The state every user passes through exactly once, and the only one the fixtures cannot
/// reach.** Every other preview in this catalog renders a demo tenant mid-work, so the first-run
/// screen has no data path to it at all: `DashboardView.fresh` is the only way to see it, and
/// without this file it would be code that ships having never been rendered.
///
/// `test/dashboard_test.dart` records the same thing from the other side, asserting that the demo
/// fixtures are deliberately NOT caught up, so a future reader knows the branch is unreachable by
/// design rather than dead.
class DashboardFreshScreenPreview extends StatelessWidget {
  /// Creates the first-run dashboard preview.
  const DashboardFreshScreenPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const ResponsiveScreenPreview(state: PreviewState.success, builder: _build);
  }

  static Widget _build(BuildContext context) => const DashboardView.fresh();
}
