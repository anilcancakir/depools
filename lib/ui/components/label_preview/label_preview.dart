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
/// The sheet a print will produce, at the page's real proportion.
///
/// ### It draws a placeholder on purpose (D18, reversed)
///
/// The sheet is an HTML template rendered to PDF on the backend, so drawing an accurate page here
/// would mean re-implementing the renderer in order to preview the renderer: two layouts of one
/// thing, drifting apart, which is exactly the duplication that reversing D18 exists to avoid.
///
/// What is kept is the page's proportion, because that is the one thing worth seeing while choosing
/// a template and it costs nothing to be right about. Once the render endpoint exists this shows the
/// server's own output, so the preview and the print are the same artefact by construction rather
/// than by care.
///
/// The cell grid this used to draw is gone rather than commented out. It was accurate about a layout
/// that is no longer ours to decide, which makes it worse than absent: a reader would trust it.
@immutable
class LabelPreview extends StatelessWidget {
  /// Which sheet template, used for the page proportion and nothing else.
  final SheetTemplate template;

  /// An already-formatted line under the sheet, for example `21 etiket · 3 sayfa`.
  final String? caption;

  /// Creates a [LabelPreview].
  const LabelPreview({super.key, required this.template, this.caption});

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
              // No `w-full h-full`: `AspectRatio` already hands this child tight constraints, and
              // wind resolves `h-full` against the ambient SCROLL scope rather than against the
              // nearest bounded parent, so it asserted by name inside the page's vertical scroll.
              // The rule is in `.claude/rules/design.md`; the component caught it before I did.
              child: WDiv(
                className: 'flex items-center justify-center',
                child: WText(
                  Lang.get('components.label_preview.placeholder'),
                  className: 'text-xs text-fg-disabled',
                ),
              ),
            ),
          ),
        ),
        ?caption != null ? WText(caption!, className: slots['caption']) : null,
      ],
    );
  }
}
