import 'package:flutter/widgets.dart';

import '../resources/views/products/barcode_scan_view.dart';
import 'preview_mock_harness.dart';
import 'responsive_screen_preview.dart';

/// Feature-screen preview: continuous barcode scanning with a batch in progress.
///
/// Rendered against a MIXED delivery rather than a shopping bag: milk and ayran next to a
/// screwdriver set, a powerbank and cable ties. A fixture of nothing but groceries is how
/// this screen would end up quietly assuming an expiry date, and half the products Depools
/// has to hold never have one.
///
/// Seven rows covering all five sources, including the two cases that only appear in a real
/// batch: a product the tenant owns but has run out of, and a barcode read six times that
/// stayed one row. The two unmatched rows sit mid-queue on purpose, because the queue is
/// ordered by last scan rather than triaged, and the count above the commit button is what
/// keeps them from disappearing upward.
class BarcodeScanScreenPreview extends StatelessWidget {
  /// Creates the barcode scan preview.
  const BarcodeScanScreenPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const ResponsiveScreenPreview(state: PreviewState.success, builder: _build);
  }

  static Widget _build(BuildContext context) => const BarcodeScanView();
}
