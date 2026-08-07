import 'package:flutter/widgets.dart';

import '../resources/views/products/assistant_view.dart';
import 'preview_mock_harness.dart';
import 'screen_preview_scaffold.dart';

/// Feature-screen preview: the assistant on a wide window.
///
/// **The same source, narrowed by width rather than branched by platform.** Above `lg` the
/// conversation sits in a centred reading column, because a message spanning 1152px is unreadable
/// and puts the send button an eye-movement from the text. DESIGN.md's layout rule is explicit
/// that `md:`/`lg:` are the tool and `ios:`/`web:` are not, and this is the screen that needs it
/// most.
///
/// It exists alongside the phone preview because a chat previewed at one width is a chat verified
/// at one width. Note the harness caveat: `appDesktop` forces a wide MediaQuery so the `lg`
/// layout resolves, while the catalog pane it renders into is narrower, so horizontal room here
/// is tighter than the real thing.
class AssistantDesktopScreenPreview extends StatelessWidget {
  /// Creates the wide-window assistant preview.
  const AssistantDesktopScreenPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const ScreenPreviewScaffold(
      state: PreviewState.success,
      chrome: PreviewChrome.appDesktop,
      builder: _build,
    );
  }

  static Widget _build(BuildContext context) => const AssistantView();
}
