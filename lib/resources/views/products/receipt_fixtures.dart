import 'package:flutter/foundation.dart';

import '../../../ui/components/receipt_line_row/receipt_line_row.dart';

/// One extracted line, as the review screen needs it.
@immutable
class ReceiptLineFixture {
  /// What the extraction read off the paper, verbatim.
  final String extracted;

  /// The product it resolved to, when it did.
  final String? productName;

  /// How far it got.
  final LineResolution resolution;

  /// Raw quantity, for the zero treatment.
  final num amount;

  /// The already-formatted quantity.
  final String formatted;

  /// The unit.
  final String unit;

  /// The already-formatted line total.
  final String price;

  /// The already-formatted destination, when one is suggested.
  final String? locationLabel;

  /// Creates a [ReceiptLineFixture].
  const ReceiptLineFixture({
    required this.extracted,
    required this.amount,
    required this.formatted,
    required this.unit,
    required this.price,
    this.productName,
    this.resolution = LineResolution.matched,
    this.locationLabel,
  });
}

/// A real Turkish grocery run, at the size the acceptance criterion names.
///
/// `receipt-ingestion.md` asks for 15 to 25 lines accepted with edits to fewer than 3.
/// This is 13 lines with 4 unresolved and 1 rejected: worse than the target on the ratio
/// that matters, which is the case worth designing against rather than the one that
/// flatters it. Shorter than the real range so the whole grouping fits one screenshot.
///
/// The extracted strings are genuine thermal-receipt truncations. "ORG KEM TAV" is the
/// example the doc itself names as the hard one, and it is unresolved here on purpose.
const List<ReceiptLineFixture> receiptLines = <ReceiptLineFixture>[
  // Unresolved: abbreviations that need the user.
  ReceiptLineFixture(
    extracted: 'ORG KEM TAV',
    resolution: LineResolution.unresolved,
    amount: 1.2,
    formatted: '1,20',
    unit: 'kg',
    price: '184,00 TL',
  ),
  ReceiptLineFixture(
    extracted: 'KSR TAM YAG 400',
    resolution: LineResolution.unresolved,
    amount: 1,
    formatted: '1',
    unit: 'adet',
    price: '128,50 TL',
  ),
  ReceiptLineFixture(
    extracted: 'MEY SUY VSN 1L',
    resolution: LineResolution.unresolved,
    amount: 3,
    formatted: '3',
    unit: 'adet',
    price: '104,70 TL',
  ),
  ReceiptLineFixture(
    extracted: 'IND 1234',
    resolution: LineResolution.unresolved,
    amount: 1,
    formatted: '1',
    unit: 'adet',
    price: '-12,00 TL',
  ),
  // Settled: matched against the tenant's own products.
  ReceiptLineFixture(
    extracted: 'PNR SUT 1LT',
    productName: 'Pınar Süt Tam Yağlı 1 lt',
    amount: 2,
    formatted: '2',
    unit: 'adet',
    price: '69,80 TL',
    locationLabel: 'Mutfak › Buzdolabı',
  ),
  ReceiptLineFixture(
    extracted: 'DURU BULGUR 1K',
    productName: 'Bulgur',
    amount: 1,
    formatted: '1',
    unit: 'kg',
    price: '42,50 TL',
    locationLabel: 'Kiler › Çekmece 2',
  ),
  ReceiptLineFixture(
    extracted: 'SOKE UN 2KG',
    productName: 'Un',
    amount: 2,
    formatted: '2',
    unit: 'kg',
    price: '58,00 TL',
    locationLabel: 'Kiler › Raf 2',
  ),
  ReceiptLineFixture(
    extracted: 'SUTAS YOG 2KG',
    productName: 'Yoğurt 2 kg',
    amount: 1,
    formatted: '1',
    unit: 'adet',
    price: '94,90 TL',
    locationLabel: 'Mutfak › Buzdolabı',
  ),
  ReceiptLineFixture(
    extracted: 'YUDUM AYC 5LT',
    productName: 'Ayçiçek Yağı 5 lt',
    amount: 1,
    formatted: '1',
    unit: 'adet',
    price: '389,00 TL',
    locationLabel: 'Kiler › Raf 2',
  ),
  ReceiptLineFixture(
    extracted: 'DANA KIYMA',
    productName: 'Kıyma',
    amount: 0.8,
    formatted: '0,80',
    unit: 'kg',
    price: '312,00 TL',
    locationLabel: 'Mutfak › Derin dondurucu',
  ),
  // Created: a product the tenant did not have yet.
  ReceiptLineFixture(
    extracted: 'ZYT YAG 5LT TARIS',
    productName: 'Tariş Zeytinyağı 5 lt',
    resolution: LineResolution.created,
    amount: 1,
    formatted: '1',
    unit: 'adet',
    price: '1.240,00 TL',
    locationLabel: 'Kiler › Raf 2',
  ),
  ReceiptLineFixture(
    extracted: 'CAY DEMLIK 1KG',
    productName: 'Çay 1 kg',
    resolution: LineResolution.created,
    amount: 1,
    formatted: '1',
    unit: 'adet',
    price: '214,00 TL',
    locationLabel: 'Kiler › Raf 1',
  ),
  // Rejected: on the receipt, not stock.
  ReceiptLineFixture(
    extracted: 'POSET',
    resolution: LineResolution.rejected,
    amount: 1,
    formatted: '1',
    unit: 'adet',
    price: '0,50 TL',
  ),
];

/// Lines the user still has to deal with.
List<ReceiptLineFixture> get unresolvedLines =>
    receiptLines.where((l) => l.resolution == LineResolution.unresolved).toList();

/// Lines that will be committed as they stand.
List<ReceiptLineFixture> get settledLines => receiptLines
    .where((l) => l.resolution == LineResolution.matched || l.resolution == LineResolution.created)
    .toList();

/// Lines the user dropped. Kept so the receipt still reconciles against the paper.
List<ReceiptLineFixture> get rejectedLines =>
    receiptLines.where((l) => l.resolution == LineResolution.rejected).toList();
