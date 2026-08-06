import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import 'label_item_row.dart';

/// Static variant-matrix preview for [LabelItemRow].
///
/// Four rows covering the two meanings of "quantity" and the two states a line can be in: a
/// lot-tracked product with a free count, a serial-tracked one whose three labels are all
/// different and whose count is therefore not editable, a product with no barcode yet, and
/// a line already printed in this batch.
///
/// Check the left edge and the right one. The glyph gutter is reserved on every row, so a
/// printed line does not shift its own name; and the serial row has no stepper at all
/// rather than a disabled one, because a disabled control invites a fight the user cannot
/// win.
class LabelItemRowPreview extends StatelessWidget {
  /// Creates the LabelItemRow preview.
  const LabelItemRowPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const WDiv(
      className: 'flex flex-col gap-6 p-6',
      children: [
        WDiv(
          className: 'flex flex-col gap-1 p-4 rounded-lg bg-surface-container',
          children: [
            LabelItemRow(name: 'Pınar Süt Tam Yağlı 1 lt', code: '8690504004073', count: 12),
            LabelItemRow(
              name: 'Makita DHP484 Darbeli Matkap',
              code: 'DPL-MK-DHP484',
              count: 3,
              mode: LabelCountMode.perSerial,
            ),
            LabelItemRow(name: 'Kablo bağı 200 mm', count: 6),
            LabelItemRow(
              name: 'Tornavida Seti PH2',
              code: '8691234567890',
              count: 4,
              isPrinted: true,
            ),
          ],
        ),
      ],
    );
  }
}
