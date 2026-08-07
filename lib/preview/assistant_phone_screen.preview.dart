import 'package:flutter/widgets.dart';

import '../resources/views/products/assistant_view.dart';
import 'preview_mock_harness.dart';
import 'screen_preview_scaffold.dart';

/// Feature-screen preview: the assistant in a phone frame, inside the real app shell.
///
/// **The same source at the other end of the width range.** `AssistantScreenPreview` renders at
/// the catalog pane's real width, where the `lg:` reading column applies; this one pins the fixed
/// 390px frame so the phone geometry can be checked without narrowing the viewport, which does
/// not work here: the catalog keeps its sidebar at every width, so a narrow window squeezes the
/// harness rather than the screen.
///
/// It is also the only place the shell's app bar and bottom nav are present, which is what
/// exposed the composer falling behind the nav: `MediaQuery` reports the window and the shell
/// spends part of it before this route gets any.
class AssistantPhoneScreenPreview extends StatelessWidget {
  /// Creates the phone-frame assistant preview.
  const AssistantPhoneScreenPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const ScreenPreviewScaffold(
      state: PreviewState.success,
      chrome: PreviewChrome.appMobile,
      builder: _build,
    );
  }

  static Widget _build(BuildContext context) => const AssistantView();
}
