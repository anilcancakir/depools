import 'package:flutter/widgets.dart';

import '../resources/views/products/barcode_scan_view.dart';
import 'preview_mock_harness.dart';
import 'responsive_screen_preview.dart';

/// Feature-screen preview: the scanner as it opens, camera live and nothing read yet.
///
/// **Not an edge case.** Every scanning session starts here, and this is the second where a
/// user decides whether the screen is working at all, so it gets its own preview rather than
/// being inferred from the populated one.
///
/// The thing to check is that the commit bar is GONE, not disabled. An earlier pass showed
/// a destination and a "0 ürünü ekle" button next to an empty queue, which is a button that
/// cannot work wearing the look of one that can: `MSButton`'s disabled state produces no
/// visible change in the primary intent, measured. The photo fallback stays, because a
/// damaged label is exactly the reason a user would be on this screen with nothing read.
class BarcodeScanEmptyScreenPreview extends StatelessWidget {
  /// Creates the empty barcode scan preview.
  const BarcodeScanEmptyScreenPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const ResponsiveScreenPreview(state: PreviewState.success, builder: _build);
  }

  static Widget _build(BuildContext context) => const BarcodeScanView.empty();
}
