import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import 'label_preview.dart';

/// Static variant-matrix preview for [LabelPreview].
///
/// Three sheets, and the point is the arithmetic between them rather than the drawing. The
/// same 9 labels waste most of an 8-up page, sit comfortably on a 24-up, and barely mark a
/// 65-up.
///
/// **This used to say that comparison is why empty cells are drawn, and nothing draws them.**
/// The cell grid went when the render moved to the server, which owns the layout now, and the
/// server's template emits only the filled cells. The waste D43 asks about is a figure per
/// template row on the screen, and here it is three proportion boxes with no render behind
/// them: no url, so no sheet.
///
/// What to check: the page must be WHITE in dark mode. It is a picture of paper, and a
/// preview that flipped with the app theme would be showing a sheet the printer cannot
/// produce. The fixed pairs live in `lib/config/depools_paper_tokens.dart`.
class LabelPreviewPreview extends StatelessWidget {
  /// Creates the LabelPreview preview.
  const LabelPreviewPreview({super.key});

  static const SheetTemplate _eightUp = SheetTemplate(
    label: "A4 · 8'li · 105×70 mm",
    pageWidthMm: 210,
    pageHeightMm: 297,
    columns: 2,
    rows: 4,
    labelWidthMm: 105,
    labelHeightMm: 70,
  );

  static const SheetTemplate _twentyFourUp = SheetTemplate(
    label: "A4 · 24'lü · 70×37 mm",
    pageWidthMm: 210,
    pageHeightMm: 297,
    columns: 3,
    rows: 8,
    labelWidthMm: 70,
    labelHeightMm: 37,
  );

  static const SheetTemplate _sixtyFiveUp = SheetTemplate(
    label: "A4 · 65'li · 38×21 mm",
    pageWidthMm: 210,
    pageHeightMm: 297,
    columns: 5,
    rows: 13,
    labelWidthMm: 38,
    labelHeightMm: 21,
  );

  @override
  Widget build(BuildContext context) {
    return const WDiv(
      className: 'flex flex-row wrap items-start gap-6 p-6',
      children: [
        WDiv(
          className: 'w-48',
          child: LabelPreview(
            template: _eightUp,
            caption: '1 sayfa · 8 / 8 kullanılır',
          ),
        ),
        WDiv(
          className: 'w-48',
          child: LabelPreview(
            template: _twentyFourUp,
            caption: '1 sayfa · 9 / 24 kullanılır',
          ),
        ),
        WDiv(
          className: 'w-48',
          child: LabelPreview(
            template: _sixtyFiveUp,
            caption: '1 sayfa · 9 / 65 kullanılır',
          ),
        ),
      ],
    );
  }
}
