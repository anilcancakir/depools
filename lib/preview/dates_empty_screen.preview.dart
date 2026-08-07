import 'package:flutter/widgets.dart';

import '../resources/views/products/dates_view.dart';
import 'preview_mock_harness.dart';
import 'screen_preview_scaffold.dart';

/// Feature-screen preview: nothing approaching.
///
/// The good outcome, and it must not read as a failure: nothing is about to spoil and no
/// warranty is about to lapse. The copy names the mechanism instead of apologising for the
/// blank, and says outright that products with no date never appear here, because a user
/// looking at an empty screen with a full pantry deserves to know why.
class DatesEmptyScreenPreview extends StatelessWidget {
  /// Creates the empty dates preview.
  const DatesEmptyScreenPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const ScreenPreviewScaffold(state: PreviewState.success, builder: _build);
  }

  static Widget _build(BuildContext context) => const DatesView.empty();
}
