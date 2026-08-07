import 'package:flutter/widgets.dart';

import '../resources/views/products/assistant_view.dart';
import 'preview_mock_harness.dart';
import 'screen_preview_scaffold.dart';

/// Feature-screen preview: the assistant mid-conversation.
///
/// Read the transcript for what is NOT in it: there is no sentence describing stock. A write
/// renders as the ledger row it produced, a shortage question renders as the shopping list
/// itself, and an approval renders as the movement pair it will write. That is D49, and it
/// is the answer to the problem `ai-assistant.md` calls the hardest in the product.
///
/// The three figures at the top are chrome rather than a message, because anything inside a
/// transcript scrolls away. They are counted from the same fixtures the product list and the
/// shopping list count, so the assistant cannot headline a number the rest of the app
/// disagrees with.
class AssistantScreenPreview extends StatelessWidget {
  /// Creates the assistant preview.
  const AssistantScreenPreview({super.key});

  @override
  Widget build(BuildContext context) {
    // **The phone shell, not bare content and not the desktop one.** This screen needs a
    // bounded height, because the transcript is the only scrolling part and
    // `PreviewChrome.none` hands the view infinity. `appDesktop` bounds the height but LIES
    // about the width (it forces a wide MediaQuery so `lg` stays true inside a narrow pane),
    // which overflowed the composer row by 107px. The phone frame bounds both honestly, and a
    // chat surface is mostly used at that width anyway.
    return const ScreenPreviewScaffold(
      state: PreviewState.success,
      chrome: PreviewChrome.appMobile,
      builder: _build,
    );
  }

  static Widget _build(BuildContext context) => const AssistantView();
}
