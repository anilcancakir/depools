import '../../../app/models/receipt.dart';
import '../../../ui/components/receipt_line_row/receipt_line_row.dart';

/// The receipt review screen as the preview catalog draws it.
///
/// **These are real [ReceiptLine]s now, not a parallel type carrying already-formatted strings.**
/// The fixture used to hold `formatted: '1'` and `price: '214,00 TL'`, which a fixture is allowed to
/// do and which meant the catalog rendered strings nothing in the app composes. Building the same
/// objects the endpoint produces makes the preview exercise the logic it exists to show: here that
/// is the quantity separator (`ProductListItem.format`) and the money label (`moneyLabel`), both of
/// which flip with the locale and neither of which a pre-written string can be wrong about.
/// `shopping_fixtures.dart` was converted first, for the same reason.
///
/// **The location chip is gone rather than carried over, and that is a schema fact.** The old
/// fixture suggested `'Kiler › Raf 1'`; `receipt_lines` has `product_id` and `global_product_id` and
/// no location column at all, so nothing computes a destination for a line. Inventing one here would
/// put a suggestion on screen that the app cannot make.
///
/// [ReceiptLine.unitPrice] and [ReceiptLine.resolvedBy] are left null on every line: this screen
/// draws neither, and a number or a cascade step invented for the catalog is exactly the kind of
/// value that later reads as something the app produced.

/// A real Turkish grocery run, at the size the acceptance criterion names.
///
/// `receipt-ingestion.md` asks for 15 to 25 lines accepted with edits to fewer than 3. This is 13
/// lines with 4 unresolved and 1 rejected: worse than the target on the ratio that matters, which is
/// the case worth designing against rather than the one that flatters it. Shorter than the real
/// range so the whole grouping fits one screenshot.
///
/// The extracted strings are genuine thermal-receipt truncations. "ORG KEM TAV" is the example the
/// doc itself names as the hard one, and it is unresolved here on purpose.
///
/// Units are UN/ECE Rec 20 codes (`C62` a piece, `KGM` a kilogram) rather than the words the old
/// fixture carried, because that is what `resolved_unit` holds and what the row has to turn into a
/// word: a fixture spelling `'adet'` would have hidden the one screen that forgot to.
const List<ReceiptLine> receiptLines = <ReceiptLine>[
  // Unresolved: abbreviations that need the user.
  ReceiptLine(
    lineNumber: 1,
    rawName: 'ORG KEM TAV',
    resolution: LineResolution.unresolved,
    quantity: 1.2,
    resolvedUnit: 'KGM',
    lineTotal: 184.00,
  ),
  ReceiptLine(
    lineNumber: 2,
    rawName: 'KSR TAM YAG 400',
    resolution: LineResolution.unresolved,
    quantity: 1,
    resolvedUnit: 'C62',
    lineTotal: 128.50,
  ),
  ReceiptLine(
    lineNumber: 3,
    rawName: 'MEY SUY VSN 1L',
    resolution: LineResolution.unresolved,
    quantity: 3,
    resolvedUnit: 'C62',
    lineTotal: 104.70,
  ),
  // A discount line, which is why one total here is negative: `moneyLabel` renders the sign and the
  // review screen has to show it rather than treat the line as unreadable.
  ReceiptLine(
    lineNumber: 4,
    rawName: 'IND 1234',
    resolution: LineResolution.unresolved,
    quantity: 1,
    resolvedUnit: 'C62',
    lineTotal: -12.00,
  ),
  // Settled: matched against the tenant's own products. `productName` is what the row draws beside
  // the printed string, so a settled line without one is a blank where the whole comparison should be.
  ReceiptLine(
    lineNumber: 5,
    rawName: 'PNR SUT 1LT',
    resolution: LineResolution.matched,
    productId: 'fixture-product-5',
    productName: 'Pınar Süt Tam Yağlı 1 lt',
    quantity: 2,
    resolvedUnit: 'C62',
    lineTotal: 69.80,
  ),
  ReceiptLine(
    lineNumber: 6,
    rawName: 'DURU BULGUR 1K',
    resolution: LineResolution.matched,
    productId: 'fixture-product-6',
    productName: 'Bulgur',
    quantity: 1,
    resolvedUnit: 'KGM',
    lineTotal: 42.50,
  ),
  ReceiptLine(
    lineNumber: 7,
    rawName: 'SOKE UN 2KG',
    resolution: LineResolution.matched,
    productId: 'fixture-product-7',
    productName: 'Un',
    quantity: 2,
    resolvedUnit: 'KGM',
    lineTotal: 58.00,
  ),
  ReceiptLine(
    lineNumber: 8,
    rawName: 'SUTAS YOG 2KG',
    resolution: LineResolution.matched,
    productId: 'fixture-product-8',
    productName: 'Yoğurt 2 kg',
    quantity: 1,
    resolvedUnit: 'C62',
    lineTotal: 94.90,
  ),
  ReceiptLine(
    lineNumber: 9,
    rawName: 'YUDUM AYC 5LT',
    resolution: LineResolution.matched,
    productId: 'fixture-product-9',
    productName: 'Ayçiçek Yağı 5 lt',
    quantity: 1,
    resolvedUnit: 'C62',
    lineTotal: 389.00,
  ),
  ReceiptLine(
    lineNumber: 10,
    rawName: 'DANA KIYMA',
    resolution: LineResolution.matched,
    productId: 'fixture-product-10',
    productName: 'Kıyma',
    quantity: 0.8,
    resolvedUnit: 'KGM',
    lineTotal: 312.00,
  ),
  // Created: a product the tenant did not have yet.
  ReceiptLine(
    lineNumber: 11,
    rawName: 'ZYT YAG 5LT TARIS',
    resolution: LineResolution.created,
    productId: 'fixture-product-11',
    productName: 'Tariş Zeytinyağı 5 lt',
    quantity: 1,
    resolvedUnit: 'C62',
    lineTotal: 1240.00,
  ),
  ReceiptLine(
    lineNumber: 12,
    rawName: 'CAY DEMLIK 1KG',
    resolution: LineResolution.created,
    productId: 'fixture-product-12',
    productName: 'Çay 1 kg',
    quantity: 1,
    resolvedUnit: 'C62',
    lineTotal: 214.00,
  ),
  // Rejected: on the receipt, not stock.
  ReceiptLine(
    lineNumber: 13,
    rawName: 'POSET',
    resolution: LineResolution.rejected,
    quantity: 1,
    resolvedUnit: 'C62',
    lineTotal: 0.50,
  ),
];

/// The receipt those lines came off, as `api/v1/receipts/{id}` sends one.
///
/// **A receipt that has already been read, which no receipt in this slice has been.** The screen's
/// reviewable state is the one worth previewing, and it is the state slice 2 produces: extraction
/// has run, nothing is confirmed. So `status` is `matched` rather than the `pending` every real row
/// carries today, and the header, the currency and the supplier are filled the way an extracted
/// receipt fills them.
///
/// The total is DERIVED from the lines rather than typed, including the discount line's negative
/// total. A header stating one figure above rows summing to another is the disagreement this app has
/// already shipped once between a list and its detail screen.
Receipt get receiptFixture => Receipt(
  id: 'fixture-receipt',
  kind: 'fis',
  status: 'matched',
  supplierName: 'Migros',
  issuedOn: DateTime(2026, 8, 5),
  totalAmount: receiptLines.fold<num>(
    0,
    (num sum, ReceiptLine line) => sum + (line.lineTotal ?? 0),
  ),
  currency: 'TRY',
  createdAt: DateTime(2026, 8, 5, 18, 22),
  linesCount: receiptLines.length,
  lines: receiptLines,
);
