import 'package:flutter/foundation.dart';

import '../../ui/components/scan_row/scan_row.dart';

/// One barcode in a scan batch, as the cascade answered it.
///
/// Replaces `ScanFixture` on the wired screen and carries the same fields, because the row widget
/// was designed against that shape and a second shape would mean two definitions of one row. What it
/// adds is the two things a live batch needs and a fixture never did: the symbology, so a non-GTIN
/// label can be committed with the identity it was read under, and the product id, so a row that
/// resolved to the tenant's own product can be written without resolving it a second time.
@immutable
class ScanEntry {
  /// The digits the scanner read, in the form it read them.
  final String barcode;

  /// The symbology, for a label that is not a GTIN. Null for a GTIN, which identifies itself.
  final String? symbology;

  /// The product it resolved to, when it did.
  final String? productName;

  /// Which stage of the cascade answered.
  final ScanSource source;

  /// How many times this barcode was scanned in this batch.
  final int count;

  /// The tenant's own product, when stage 1 answered. Null for every other stage.
  final String? productId;

  /// The unit the count is in.
  final String unit;

  /// When this code was SCANNED, as a monotonic counter rather than a clock.
  ///
  /// **The queue is ordered by this and not by arrival, because the two differ.** A local hit
  /// answers in about five milliseconds and an Open Food Facts lookup in five hundred, so a row
  /// inserted when its answer lands puts the OLDER scan above the newer one: the user reads a row
  /// jumping to the top for a carton they scanned two cartons ago. D40's reason for newest-first is
  /// feedback, and feedback that points at the wrong row is worse than none.
  ///
  /// A counter rather than a `DateTime` because it only has to order, and two reads inside one
  /// millisecond are ordinary on a camera stream.
  final int sequence;

  /// Creates a [ScanEntry].
  const ScanEntry({
    required this.barcode,
    required this.count,
    this.sequence = 0,
    this.symbology,
    this.productName,
    this.source = ScanSource.unmatched,
    this.productId,
    this.unit = 'adet',
  });

  /// Whether this row will be written to stock as it stands.
  bool get isSettled => source != ScanSource.unmatched;

  /// The same row scanned once more, taking the new read's place in the queue.
  ///
  /// The sequence moves because a repeat IS a scan: the row has to come back to the front or the
  /// sixth yoghurt increments a row that has already scrolled away (D40).
  ScanEntry incremented({required int sequence}) =>
      copyWith(count: count + 1, sequence: sequence);

  /// A copy with the named fields replaced.
  ScanEntry copyWith({
    String? productName,
    ScanSource? source,
    int? count,
    int? sequence,
    String? productId,
    String? unit,
  }) => ScanEntry(
    barcode: barcode,
    symbology: symbology,
    sequence: sequence ?? this.sequence,
    productName: productName ?? this.productName,
    source: source ?? this.source,
    count: count ?? this.count,
    productId: productId ?? this.productId,
    unit: unit ?? this.unit,
  );

  /// The row the cascade's answer describes.
  ///
  /// **The mapping is not one-to-one and the gap is deliberate.** The endpoint reports which STAGE
  /// answered; `ScanSource` reports how far to trust it, and those are different questions. A
  /// community row is `catalog` because somebody here confirmed it; an Open Food Facts row is
  /// `unverified` because nobody here has, which is what criterion 7 asks to be shown. `recalled` is
  /// not produced from a response at all: it means the user's own past answer replayed, which is a
  /// fact about this tenant's history rather than about the cascade.
  ///
  /// An unknown value maps to `unverified` rather than to `own`, because a stage this client has not
  /// heard of is a stage it cannot vouch for, and guessing upward is the only direction that puts a
  /// wrong claim on the screen.
  static ScanSource sourceOf(String? apiSource) => switch (apiSource) {
    'own' => ScanSource.own,
    'community' => ScanSource.catalog,
    'off' => ScanSource.unverified,
    _ => ScanSource.unverified,
  };
}
