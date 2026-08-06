import 'package:flutter/foundation.dart';

import '../../../ui/components/label_item_row/label_item_row.dart';
import '../../../ui/components/label_preview/label_preview.dart';

/// One product in a print batch, as the label screen needs it.
@immutable
class LabelItemFixture {
  /// The product name, the label's first line.
  final String name;

  /// The code that will be printed, or null when one has to be generated.
  final String? code;

  /// How many labels this line contributes.
  final int count;

  /// Where the count comes from.
  final LabelCountMode mode;

  /// Whether this line has already been printed in this batch.
  final bool isPrinted;

  /// Creates a [LabelItemFixture].
  const LabelItemFixture({
    required this.name,
    required this.count,
    this.code,
    this.mode = LabelCountMode.free,
    this.isPrinted = false,
  });
}

/// The sheet catalog, ported in shape from the MVP's `config/labels.php`.
///
/// Four of the seventeen, chosen so the arithmetic is visibly different: 8-up wastes a
/// third of a page on a small batch, 24-up wastes nothing because its grid exactly fills
/// A4, and 65-up is small enough that a location line stops fitting. The catalog is one of
/// the open questions in `labeling-and-printing.md`: which sheets Turkish stationery shops
/// actually stock is unverified, and a catalog nobody can buy makes the feature useless.
const List<SheetTemplate> sheetTemplates = <SheetTemplate>[
  SheetTemplate(
    label: "A4 · 8'li · 105×70 mm",
    pageWidthMm: 210,
    pageHeightMm: 297,
    columns: 2,
    rows: 4,
    labelWidthMm: 105,
    labelHeightMm: 70,
  ),
  SheetTemplate(
    label: "A4 · 14'lü · 99×38 mm",
    pageWidthMm: 210,
    pageHeightMm: 297,
    columns: 2,
    rows: 7,
    labelWidthMm: 99,
    labelHeightMm: 38,
  ),
  SheetTemplate(
    label: "A4 · 24'lü · 70×37 mm",
    pageWidthMm: 210,
    pageHeightMm: 297,
    columns: 3,
    rows: 8,
    labelWidthMm: 70,
    labelHeightMm: 37,
  ),
  SheetTemplate(
    label: "A4 · 65'li · 38×21 mm",
    pageWidthMm: 210,
    pageHeightMm: 297,
    columns: 5,
    rows: 13,
    labelWidthMm: 38,
    labelHeightMm: 21,
  ),
];

/// What can go on a label, in the order it prints.
const List<String> labelFieldOptions = <String>['Ürün adı', 'Barkod', 'Konum', 'Ekip adı'];

/// A relabelling run in a workshop, which is the case that put this feature in v1.
///
/// **Mixed tracking on purpose.** Two lot-tracked products with free quantities, one
/// serial-tracked product whose three labels are all different, and one product with no
/// barcode at all. Those are three different meanings of the word "quantity" and D45 is
/// what separates them; a fixture of four identical lot products would have let the screen
/// quietly assume one.
///
/// One line is already printed, because criterion 5 requires a partially printed batch to
/// be resumable and a batch with nothing printed cannot demonstrate it.
const List<LabelItemFixture> labelBatch = <LabelItemFixture>[
  LabelItemFixture(name: 'Pınar Süt Tam Yağlı 1 lt', code: '8690504004073', count: 12),
  LabelItemFixture(
    name: 'Makita DHP484 Darbeli Matkap',
    code: 'DPL-MK-DHP484',
    count: 3,
    mode: LabelCountMode.perSerial,
  ),
  // No barcode. Never blocked: a Code128 code with a tenant prefix gets generated, which
  // is also why an internal label can never be read as a manufacturer EAN-13.
  LabelItemFixture(name: 'Kablo bağı 200 mm', count: 6),
  LabelItemFixture(name: 'Tornavida Seti PH2', code: '8691234567890', count: 4, isPrinted: true),
];

/// The labels still to print.
int get pendingLabels =>
    labelBatch.where((i) => !i.isPrinted).fold(0, (sum, item) => sum + item.count);

/// How many sheets [pendingLabels] needs on [template].
int sheetsFor(SheetTemplate template) =>
    pendingLabels == 0 ? 0 : (pendingLabels + template.perSheet - 1) ~/ template.perSheet;

/// The cells that get printed blank on [template], across every sheet.
///
/// This is the figure that separates the catalog, and the page count is not: 24-up and
/// 65-up both fit this batch on one sheet, which makes them look identical until you see
/// that one wastes 3 labels and the other wastes 44.
int wastedCells(SheetTemplate template) => sheetsFor(template) * template.perSheet - pendingLabels;

/// How many cells the last sheet uses. Equals a full sheet when the batch divides evenly.
int lastSheetFill(SheetTemplate template) {
  final int remainder = pendingLabels % template.perSheet;
  return remainder == 0 ? template.perSheet : remainder;
}
