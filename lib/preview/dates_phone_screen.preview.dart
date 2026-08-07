import 'package:flutter/widgets.dart';

import '../resources/views/products/dates_view.dart';
import 'preview_mock_harness.dart';
import 'screen_preview_scaffold.dart';

/// Feature-screen preview: the dates screen in a phone frame, inside the real app shell.
///
/// **Added to isolate an overflow, and it should have existed anyway.** Every list screen in this
/// app was verified at catalog width only, so `LotRow` had never been laid out at 390px despite
/// being the densest row in the product: a name, up to two badges, a meta line and a right-aligned
/// quantity, all on a phone.
///
/// The dashboard is what surfaced it, because the dashboard is the only screen that renders a
/// `LotRow` inside a phone frame. That is an accident of which previews exist rather than a fact
/// about the dashboard, and this file removes the accident.
class DatesPhoneScreenPreview extends StatelessWidget {
  /// Creates the phone-frame dates preview.
  const DatesPhoneScreenPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const ScreenPreviewScaffold(
      state: PreviewState.success,
      chrome: PreviewChrome.appMobile,
      builder: _build,
    );
  }

  static Widget _build(BuildContext context) => const DatesView();
}
