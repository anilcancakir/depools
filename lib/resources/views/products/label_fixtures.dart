import '../../../app/models/print_batch.dart';
import '../../../ui/components/label_item_row/label_item_row.dart';
import '../../../ui/components/label_preview/label_preview.dart';

/// One relabelling run in a workshop, which is the case that put this feature in v1.
///
/// **`LabelItemFixture` is gone and `PrintBatchLine` replaced it**, because `flutter-app.md` says to
/// replace a fixture rather than shadow it: two types for one thing diverge the moment the API
/// changes. What is left here is the DATA, which is what a preview needs.
///
/// The arithmetic went with the move. `pendingLabels`, `sheetsFor`, `wastedCells` and `lastSheetFill`
/// were computed here against a fixture; the screen computes them from whatever batch it holds, and
/// the pending count now comes from the server so the two cannot disagree.
///
/// **Mixed tracking on purpose.** Two lot-tracked products with free quantities, one serial-tracked
/// product whose label identifies one physical unit, and one product with no barcode at all. Those are
/// three different meanings of the word "quantity" and D45 is what separates them; a fixture of four
/// identical lot products would have let the screen quietly assume one.
///
/// One line is already printed, because criterion 5 requires a partially printed batch to be
/// resumable and a batch with nothing printed cannot demonstrate it.
const PrintBatch labelBatch = PrintBatch(
  id: 'batch-1',
  name: 'Atölye yeniden etiketleme',
  template: 'a4_8_up_105x70',
  fields: <String>['name', 'code'],
  stickerCount: 22,
  pendingStickerCount: 18,
  lines: <PrintBatchLine>[
    PrintBatchLine(position: 1, name: 'Pınar Süt Tam Yağlı 1 lt', code: '8690504004073', count: 12),
    PrintBatchLine(
      position: 2,
      name: 'Makita DHP484 Darbeli Matkap',
      serial: 'DPL-MK-DHP484',
      count: 1,
      mode: LabelCountMode.perSerial,
    ),
    // No barcode. Never blocked: the server generates a Code 128 code with a tenant prefix, which is
    // also why an internal label can never be read as a manufacturer EAN-13.
    PrintBatchLine(position: 3, name: 'Kablo bağı 200 mm', count: 5),
    PrintBatchLine(
      position: 4,
      name: 'Tornavida Seti PH2',
      code: '8691234567890',
      count: 4,
      isPrinted: true,
      printCount: 1,
    ),
  ],
);

/// The sheet catalogue, as `labels/templates` sends it.
///
/// Four of the four the backend ships, which is the whole catalogue rather than a sample: each matches
/// a standard A4 die-cut layout and the arithmetic is visibly different between them. 8-up wastes a
/// third of a page on a small batch, 24-up wastes nothing because its grid exactly fills A4, and 65-up
/// is small enough that a barcode stops fitting.
///
/// `maxCodeLength` is the server's own figure and it is the point of the smallest entry: seven
/// characters, so a 13-digit GTIN on that sheet is a barcode nothing can read.
const List<SheetTemplate> sheetTemplates = <SheetTemplate>[
  SheetTemplate(
    key: 'a4_8_up_105x70',
    label: "A4 · 8'li · 105×70 mm",
    pageWidthMm: 210,
    pageHeightMm: 297,
    columns: 2,
    rows: 4,
    labelWidthMm: 105,
    labelHeightMm: 70,
    maxCodeLength: 32,
  ),
  SheetTemplate(
    key: 'a4_14_up_99x38',
    label: "A4 · 14'lü · 99×38 mm",
    pageWidthMm: 210,
    pageHeightMm: 297,
    columns: 2,
    rows: 7,
    labelWidthMm: 99,
    labelHeightMm: 38,
    maxCodeLength: 29,
  ),
  SheetTemplate(
    key: 'a4_24_up_70x37',
    label: "A4 · 24'lü · 70×37 mm",
    pageWidthMm: 210,
    pageHeightMm: 297,
    columns: 3,
    rows: 8,
    labelWidthMm: 70,
    labelHeightMm: 37,
    maxCodeLength: 19,
  ),
  SheetTemplate(
    key: 'a4_65_up_38x21',
    label: "A4 · 65'li · 38×21 mm",
    pageWidthMm: 210,
    pageHeightMm: 297,
    columns: 5,
    rows: 13,
    labelWidthMm: 38,
    labelHeightMm: 21,
    maxCodeLength: 7,
  ),
];

/// The same batch on the smallest sheet, where a barcode stops fitting.
///
/// The 13-digit GTIN needs 49.5 mm at GS1's absolute floor and the label offers 35 mm, so the screen's
/// callout has something real to name rather than a correlation with the label's height.
const PrintBatch tightBatch = PrintBatch(
  id: 'batch-2',
  template: 'a4_65_up_38x21',
  fields: <String>['name', 'code'],
  stickerCount: 12,
  pendingStickerCount: 12,
  lines: <PrintBatchLine>[
    PrintBatchLine(position: 1, name: 'Pınar Süt Tam Yağlı 1 lt', code: '8690504004073', count: 12),
  ],
);
