import 'package:flutter/widgets.dart';

import '../resources/views/products/assistant_view.dart';
import 'preview_mock_harness.dart';
import 'screen_preview_scaffold.dart';

/// Feature-screen preview: the assistant before the first message.
///
/// **The first run is not a lesser state.** It is where a user decides whether this thing
/// understands Turkish grocery sentences, and a blank box answers that with nothing. So the
/// openers are sample utterances in the user's own words rather than a feature list: the
/// question a new user has is not "what can this do" but "what do I type".
///
/// The overview is present here too, which is the point of it being chrome: a user who has
/// never sent a message can still see what needs attention.
class AssistantFreshScreenPreview extends StatelessWidget {
  /// Creates the first-run assistant preview.
  const AssistantFreshScreenPreview({super.key});

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

  static Widget _build(BuildContext context) => const AssistantView.fresh();
}
