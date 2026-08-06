import 'package:flutter/foundation.dart';

import '../../../ui/components/scan_row/scan_row.dart';

/// One barcode in a scan batch, as the scan screen needs it.
@immutable
class ScanFixture {
  /// The digits the scanner read.
  final String barcode;

  /// The product it resolved to, when it did.
  final String? productName;

  /// Which stage of the cascade answered.
  final ScanSource source;

  /// How many times this barcode was scanned in this batch.
  final int count;

  /// The unit the count is in.
  final String unit;

  /// The already-formatted stock on hand, when the product is the tenant's own.
  final String? onHandFormatted;

  /// Creates a [ScanFixture].
  const ScanFixture({
    required this.barcode,
    required this.count,
    this.productName,
    this.source = ScanSource.own,
    this.unit = 'adet',
    this.onHandFormatted,
  });

  /// Whether this row will be written to stock as it stands.
  bool get isSettled => source != ScanSource.unmatched;
}

/// A mixed delivery being unpacked at a receiving bench.
///
/// **Mixed on purpose, and not just food.** Milk and ayran sit next to a screwdriver set,
/// a powerbank and cable ties, because Depools is not a pantry app: a hardware shop
/// unpacking a shipment is the same flow, and a fixture full of groceries would have let
/// every design decision here quietly assume an expiry date.
///
/// **Ordered by last scan, most recent first**, which is D40's consequence rather than a
/// cosmetic choice. A repeat scan increments an existing row, so if the queue were ordered
/// by first-seen, the sixth yoghurt would increment a row that had already scrolled away
/// and the user would get no feedback for a scan that worked. The two unmatched rows are
/// deliberately NOT floated to the top: while the camera is live, feedback beats triage,
/// and the count above the commit button is what keeps them from being forgotten.
///
/// Compare `receiptLines`, which groups unresolved first. The paper is static and triage
/// IS the task there; here the camera is running and the last scan has to be visible.
const List<ScanFixture> scanBatch = <ScanFixture>[
  // Scanned last, so it leads. The barcode missed the whole cascade once before and the
  // user typed the product in; this is their own answer replayed.
  ScanFixture(
    barcode: '8680000998877',
    productName: 'Kablo bağı 200 mm',
    source: ScanSource.recalled,
    count: 1,
  ),
  ScanFixture(barcode: '8680000123456', source: ScanSource.unmatched, count: 1),
  ScanFixture(
    barcode: '6941487206643',
    productName: 'Powerbank 10000 mAh',
    source: ScanSource.unverified,
    count: 2,
  ),
  ScanFixture(
    barcode: '8690632073415',
    productName: 'Sütaş Ayran 250 ml',
    source: ScanSource.catalog,
    count: 6,
  ),
  // The case the MVP broke: a product already in the tenant's own inventory.
  ScanFixture(
    barcode: '8690504004073',
    productName: 'Pınar Süt Tam Yağlı 1 lt',
    count: 3,
    onHandFormatted: '2',
  ),
  ScanFixture(barcode: '4011200296908', source: ScanSource.unmatched, count: 2),
  // Known product, none left. `Mevcut: 0 adet` is the most useful thing a scan can say,
  // and it is only visible because zero is treated as a value rather than as absence.
  ScanFixture(
    barcode: '8691234567890',
    productName: 'Tornavida Seti PH2',
    count: 1,
    onHandFormatted: '0',
  ),
];

/// The rows that will be written to stock as they stand.
List<ScanFixture> get settledScans => scanBatch.where((s) => s.isSettled).toList();

/// The rows nothing could resolve. Counted next to the commit button so a queue ordered
/// by recency does not let them disappear upward.
List<ScanFixture> get unmatchedScans =>
    scanBatch.where((s) => s.source == ScanSource.unmatched).toList();
