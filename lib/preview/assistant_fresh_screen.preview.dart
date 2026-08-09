import 'package:flutter/widgets.dart';

import '../resources/views/products/assistant_view.dart';
import 'preview_mock_harness.dart';
import 'responsive_screen_preview.dart';

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
    return const ResponsiveScreenPreview(state: PreviewState.success, builder: _build, bounded: true);
  }

  static Widget _build(BuildContext context) => const AssistantView.fresh();
}
