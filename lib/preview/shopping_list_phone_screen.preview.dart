import 'package:flutter/widgets.dart';

import '../resources/views/products/shopping_list_view.dart';
import 'preview_mock_harness.dart';
import 'screen_preview_scaffold.dart';

/// Feature-screen preview: shopping list in a phone frame, inside the real app shell.
///
/// **Added because catalog-width-only verification turned out to be systematic.** `LotRow`
/// overflowed its row by 16 to 36 logical pixels at 390px and nobody had seen it, because the dates
/// screen had never once been laid out at phone width. It surfaced only when the dashboard became
/// the first phone-framed screen to render one, which is an accident of which previews exist rather
/// than a fact about the dashboard.
///
/// Here the specific risk is that tickable rows with a leading control and a trailing amount.
///
/// The fixed 390px frame is the only honest way to check it: narrowing the viewport squeezes the
/// catalog harness rather than the screen, because the catalog keeps its sidebar at every width.
/// This frame is also the only place the shell's app bar and bottom nav are mounted.
class ShoppingListPhoneScreenPreview extends StatelessWidget {
  /// Creates the phone-frame shopping list preview.
  const ShoppingListPhoneScreenPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const ScreenPreviewScaffold(
      state: PreviewState.success,
      chrome: PreviewChrome.appMobile,
      builder: _build,
    );
  }

  static Widget _build(BuildContext context) => const ShoppingListView();
}
