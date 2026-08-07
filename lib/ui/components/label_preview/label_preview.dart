import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import 'label_preview.recipe.dart';

/// One entry from the label size and page catalog, in millimetres.
///
/// The catalog itself is ported from the MVP's `config/labels.php` (17 label sizes, 5 page
/// sizes, multi-up definitions like `a4_8_up_105x70`), which was the one part of that
/// feature worth keeping.
@immutable
class SheetTemplate {
  /// The human name, for example `A4 · 8'li · 105×70 mm`.
  final String label;

  /// Page width in millimetres.
  final int pageWidthMm;

  /// Page height in millimetres.
  final int pageHeightMm;

  /// Labels across.
  final int columns;

  /// Labels down.
  final int rows;

  /// One label's width in millimetres.
  final int labelWidthMm;

  /// One label's height in millimetres.
  final int labelHeightMm;

  /// Creates a [SheetTemplate].
  const SheetTemplate({
    required this.label,
    required this.pageWidthMm,
    required this.pageHeightMm,
    required this.columns,
    required this.rows,
    required this.labelWidthMm,
    required this.labelHeightMm,
  });

  /// Labels per sheet.
  int get perSheet => columns * rows;

  /// The horizontal margin the grid leaves, halved, in millimetres.
  int get sideMarginMm => (pageWidthMm - columns * labelWidthMm) ~/ 2;

  /// The vertical margin the grid leaves, halved, in millimetres.
  int get topMarginMm => (pageHeightMm - rows * labelHeightMm) ~/ 2;
}

/// **LabelPreview**
///
/// The sheet as it will come out of the printer: the grid at true proportions, the filled
/// cells, and the empty ones.
///
/// **The geometry is Flutter, the paint is Wind, and that split is forced.** Core Law 3
/// forbids interpolating a value into a className, so `w-[${mm * scale}px]` is not
/// available and a to-scale grid cannot be expressed in tokens. Instead an `AspectRatio`
/// pins the page to its real proportions and every band is an `Expanded` whose flex is the
/// millimetre figure times ten. Those integers come straight from the template, so the
/// preview is exact by construction rather than by a scale factor somebody has to keep
/// right. Wind then paints inside the cells.
///
/// **The cells are stylised, not typeset, and that is the honest choice.** An A4 sheet in a
/// column half a screen wide puts 9pt label text at about six pixels. Rendering it anyway
/// would produce a preview that appears to show content while showing noise, and rendering
/// it LARGER would break criterion 7 in the direction that matters: a user would approve a
/// name that does not actually fit. So a filled cell shows the shape of a label (a name
/// bar, a barcode, a meta bar) and [LabelCard] beside it shows one label at a size a person
/// can read.
///
/// **Empty cells are drawn.** The unused half of a sheet is the single most useful thing
/// this preview says, because paper is the consumable and a user deciding between 8-up and
/// 24-up is deciding how much of it to waste.
@immutable
class LabelPreview extends StatelessWidget {
  /// The sheet layout.
  final SheetTemplate template;

  /// How many cells on this sheet carry a label. Cells beyond it are empty.
  final int filled;

  /// The barcode whose digits drive the stylised bar pattern, so the drawing is derived
  /// from real data rather than being decorative noise.
  final String barcode;

  /// The already-formatted caption under the sheet, for example
  /// `'3 sayfa · son sayfada 1 etiket'`.
  final String? caption;

  /// Creates a [LabelPreview].
  const LabelPreview({
    super.key,
    required this.template,
    required this.filled,
    required this.barcode,
    this.caption,
  });

  @override
  Widget build(BuildContext context) {
    final slots = labelPreviewRecipe()();

    return WDiv(
      className: slots['root'],
      children: [
        WDiv(
          className: slots['tray'],
          child: WDiv(
            className: slots['page'],
            child: AspectRatio(
              aspectRatio: template.pageWidthMm / template.pageHeightMm,
              child: Column(children: _bands(slots)),
            ),
          ),
        ),
        if (caption != null) WText(caption!, className: slots['caption']),
      ],
    );
  }

  /// The page split top to bottom: margin, one band per label row, margin.
  ///
  /// Flexes are millimetres times ten so a half-millimetre template still lands on an
  /// integer. A zero margin contributes no band at all, because `Expanded` requires a
  /// positive flex.
  List<Widget> _bands(Map<String, String> slots) {
    final int margin = template.topMarginMm * 10;
    return <Widget>[
      if (margin > 0) Expanded(flex: margin, child: const SizedBox.shrink()),
      for (int row = 0; row < template.rows; row++)
        Expanded(
          flex: template.labelHeightMm * 10,
          child: Row(children: _cells(slots, row)),
        ),
      if (margin > 0) Expanded(flex: margin, child: const SizedBox.shrink()),
    ];
  }

  /// One label row, left to right.
  List<Widget> _cells(Map<String, String> slots, int row) {
    final int margin = template.sideMarginMm * 10;
    return <Widget>[
      if (margin > 0) Expanded(flex: margin, child: const SizedBox.shrink()),
      for (int column = 0; column < template.columns; column++)
        Expanded(
          flex: template.labelWidthMm * 10,
          child: row * template.columns + column < filled ? _filledCell(slots) : _emptyCell(slots),
        ),
      if (margin > 0) Expanded(flex: margin, child: const SizedBox.shrink()),
    ];
  }

  /// A cell carrying a label: name bar, barcode, meta bar.
  ///
  /// The proportions are the ones a real label uses, so the sheet reads as a sheet of
  /// labels rather than a grid of boxes.
  Widget _filledCell(Map<String, String> slots) {
    return WDiv(
      className: slots['cell'],
      child: Column(
        children: <Widget>[
          const Spacer(flex: 3),
          Expanded(flex: 2, child: _bar(slots, 0.72)),
          const Spacer(flex: 1),
          Expanded(flex: 7, child: _barcode(slots)),
          const Spacer(flex: 1),
          Expanded(flex: 2, child: _bar(slots, 0.44)),
          const Spacer(flex: 3),
        ],
      ),
    );
  }

  /// A text line, drawn rather than typeset.
  Widget _bar(Map<String, String> slots, double widthFactor) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      alignment: Alignment.centerLeft,
      child: WDiv(className: slots['textBar']),
    );
  }

  /// The barcode, with bar widths derived from the digits.
  ///
  /// Deterministic on purpose: two different products draw two different patterns, and the
  /// same product draws the same one every time. A random or uniform pattern would be
  /// decoration, and decoration in a preview whose job is fidelity is a small lie.
  Widget _barcode(Map<String, String> slots) {
    final List<int> digits = barcode.codeUnits
        .where((c) => c >= 0x30 && c <= 0x39)
        .map((c) => c - 0x30)
        .toList();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final int digit in digits) ...<Widget>[
          Expanded(
            flex: 1 + digit % 3,
            child: WDiv(className: slots['bar']),
          ),
          Expanded(flex: 1 + (digit + 1) % 2, child: const SizedBox.shrink()),
        ],
      ],
    );
  }

  /// An unused cell, outlined so the waste is visible before paper is committed.
  Widget _emptyCell(Map<String, String> slots) {
    return WDiv(
      className: slots['emptyCell'],
      child: WDiv(className: slots['emptyMark']),
    );
  }
}
