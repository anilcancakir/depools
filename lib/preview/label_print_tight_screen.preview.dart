import 'package:flutter/widgets.dart';

import '../resources/views/products/label_print_view.dart';
import 'preview_mock_harness.dart';
import 'screen_preview_scaffold.dart';

/// Feature-screen preview: the same batch on the smallest sheet in the catalog.
///
/// At 38×21 mm the location line stops fitting, which is the state
/// `labeling-and-printing.md` singles out: say WHICH field will not fit rather than
/// silently truncating. So the label card keeps the name whole and names the casualty, and
/// a callout below offers the two real ways out (drop the field, or take a bigger layout).
///
/// It is also the sheet where the paper arithmetic inverts: 65 cells a page turns three
/// sheets into one, with most of it used. Comparing this against the 8-up preview is the
/// comparison a user makes before spending labels.
class LabelPrintTightScreenPreview extends StatelessWidget {
  /// Creates the tight-layout label print preview.
  const LabelPrintTightScreenPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const ScreenPreviewScaffold(state: PreviewState.success, builder: _build);
  }

  static Widget _build(BuildContext context) => const LabelPrintView.tight();
}
