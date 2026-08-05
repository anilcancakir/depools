import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart' show WDiv, WText;

import 'preview_mock_harness.dart';
import 'screen_preview_scaffold.dart';

/// Navigation preview: the authenticated app shell on its MOBILE layout, the
/// bottom navigation bar + drawer, rendered in a phone-width frame. The body is
/// an empty placeholder card so the preview focuses on the navigation chrome,
/// not a crammed screen.
class BottomMenuPreview extends StatelessWidget {
  /// Creates the bottom-menu navigation preview.
  const BottomMenuPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const ScreenPreviewScaffold(
      state: PreviewState.success,
      chrome: PreviewChrome.appMobile,
      builder: _build,
    );
  }

  static Widget _build(BuildContext context) => const WDiv(
    className: 'p-6',
    child: WDiv(
      className: '''
        w-full h-80 rounded-xl
        border border-color-border bg-surface-container
        flex items-center justify-center
      ''',
      child: WText('Page content', className: 'text-fg-muted text-sm'),
    ),
  );
}
