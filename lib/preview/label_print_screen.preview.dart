import 'package:flutter/widgets.dart';

import '../resources/views/products/label_fixtures.dart';
import '../resources/views/products/label_print_view.dart';
import 'preview_mock_harness.dart';
import 'responsive_screen_preview.dart';

/// Feature-screen preview: printing a batch of labels on the default 8-up sheet.
///
/// The batch is a workshop relabelling run with mixed tracking: two lot-tracked products
/// whose counts are free, a serial-tracked drill whose three labels are all different and
/// whose count therefore is not editable, and a product with no barcode that will get a
/// generated one. Those are three different meanings of "quantity" in one list, which is
/// what D45 exists to keep apart.
///
/// One line is already printed, because criterion 5 asks for a partially printed batch to
/// be resumable and a batch with nothing printed cannot show it.
///
/// What to check: the sheet is white in dark mode, its proportions are A4 whatever the
/// column width, and the empty cells on the last page are visible. That waste is the thing
/// a template choice is actually about.
class LabelPrintScreenPreview extends StatelessWidget {
  /// Creates the label print preview.
  const LabelPrintScreenPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const ResponsiveScreenPreview(state: PreviewState.success, builder: _build);
  }

  static Widget _build(BuildContext context) => LabelPrintView.preview(labelBatch, sheetTemplates);
}
