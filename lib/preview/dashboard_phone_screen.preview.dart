import 'package:flutter/widgets.dart';

import '../resources/views/dashboard_view.dart';
import 'preview_mock_harness.dart';
import 'screen_preview_scaffold.dart';

/// Feature-screen preview: the dashboard in a phone frame, inside the real app shell.
///
/// **The dashboard has two layouts and only one of them is visible in the catalog pane.** The
/// counters are `grid-cols-2 md:grid-cols-4` and the capture buttons are `flex-col md:flex-row`,
/// so the wide preview never renders the phone arrangement at all: a 2x2 counter grid and three
/// stacked full-width buttons.
///
/// The fixed 390px frame is the only honest way to see it. Narrowing the viewport does not work
/// here, because the catalog keeps its sidebar at every width and squeezes the harness rather than
/// the screen, which is how a 400px "mobile" measurement produced a confident wrong answer once
/// already.
///
/// This frame is also the only place the shell's app bar and bottom nav are mounted, and the
/// bottom nav is what the dashboard's five entries land in.
class DashboardPhoneScreenPreview extends StatelessWidget {
  /// Creates the phone-frame dashboard preview.
  const DashboardPhoneScreenPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const ScreenPreviewScaffold(
      state: PreviewState.success,
      chrome: PreviewChrome.appMobile,
      builder: _build,
    );
  }

  static Widget _build(BuildContext context) => const DashboardView();
}
