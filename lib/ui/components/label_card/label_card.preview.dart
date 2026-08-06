import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import 'label_card.dart';

/// Static variant-matrix preview for [LabelCard].
///
/// Four cards: a large label that fits, the same content on a small label where the
/// location does not fit, a minimal label carrying only a code, and an internal code that
/// was generated rather than scanned.
///
/// The overflow card is the one to read. `labeling-and-printing.md` requires the app to say
/// WHICH field will not fit rather than truncating, so the name stays whole and a line in
/// the destructive tone names the casualty. A card that silently cut the text would look
/// tidier here and cost a sheet of 200 in real life.
///
/// The card is white in both appearances, on purpose. See `depools_paper_tokens.dart`.
class LabelCardPreview extends StatelessWidget {
  /// Creates the LabelCard preview.
  const LabelCardPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const WDiv(
      className: 'flex flex-row wrap items-start gap-4 p-6',
      children: [
        WDiv(
          className: 'w-52',
          child: LabelCard(
            name: 'Pınar Süt Tam Yağlı 1 lt',
            meta: 'Mutfak › Buzdolabı',
            code: '8690504004073',
          ),
        ),
        WDiv(
          className: 'w-40',
          child: LabelCard(
            name: 'Pınar Süt Tam Yağlı 1 lt',
            meta: 'Mutfak › Buzdolabı',
            code: '8690504004073',
            overflowField: 'Konum',
            size: LabelCardSize.sm,
          ),
        ),
        WDiv(
          className: 'w-40',
          child: LabelCard(name: 'Kablo bağı 200 mm', code: 'DPL-000418', size: LabelCardSize.sm),
        ),
        WDiv(
          className: 'w-52',
          child: LabelCard(
            name: 'Makita DHP484 Darbeli Matkap',
            meta: 'Depo › Raf A · MK-DHP484-002391',
            code: 'DPL-MK-DHP484',
          ),
        ),
      ],
    );
  }
}
