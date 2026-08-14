import 'package:flutter/foundation.dart';

import 'scan_source.dart';

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

  /// The brand, when a draft carried one. Never sent for a row the tenant already owns.
  final String? brand;

  /// Whether a created product goes to the shared catalogue (D117: ticked by default).
  final bool contribute;

  /// Whether the cascade is still being asked what this code is.
  ///
  /// **The row exists during its own lookup, and it used not to.** A read produced nothing on screen
  /// until its answer arrived, which is around five milliseconds for a local hit and much longer for
  /// stage 3: an Open Food Facts round trip, and a community row goes through `CatalogueTranslator`
  /// synchronously on top of that. So a scan of something new looked ignored for as long as the
  /// slowest stage took, at a bench where the next carton is already in the user's hands.
  ///
  /// Orthogonal to [source] rather than a value of it, because a pending row has no answer to be
  /// trusted or distrusted: [source] says how far to believe a claim, and there is no claim yet.
  final bool pending;

  /// Whether the user has been shown this row's card.
  ///
  /// **A row that will CREATE a product is confirmed once, and this is what stops it being twice.**
  /// A catalogue answer is a claim about somebody else's data, so it gets one look before it becomes
  /// the tenant's own product. Without this flag the second read of the same carton would re-open the
  /// sheet, which is the modal-per-scan `barcode-and-catalog.md` rejects outright.
  ///
  /// Records that the card was SHOWN, not that the user agreed with it: cancelling still counts, and
  /// the row keeps whatever the cascade said. Tapping the row re-opens it for anybody who wants
  /// another look.
  final bool asked;

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
    this.unit = defaultUnit,
    this.brand,
    this.contribute = true,
    this.pending = false,
    this.asked = false,
  });

  /// What a row is counted in when nothing has said otherwise.
  ///
  /// Named rather than repeated, because three places compared against the literal and a fourth wrote
  /// it: the constructor's default, the batch line deciding whether the unit was CHOSEN, and the row
  /// widget. It is also the value that is wrong on an English screen, so when the vocabulary changes
  /// this is the one place that has to.
  static const String defaultUnit = 'adet';

  /// What makes two reads the same read.
  ///
  /// **The symbology is part of it, because the server says so**: the same characters as Code128 and
  /// as a QR are two different labels, and `Barcode::forCode()` keys on the pair. Defined once and
  /// used by both the batch and the camera's presence gate, which is what stops them disagreeing:
  /// the gate keyed on the code alone would suppress a QR because a Code128 of the same text had
  /// just been seen, while the batch was busy keeping them apart.
  static String keyOf(String code, String? symbology) => '$code|${symbology ?? ''}';

  /// This row's identity.
  String get key => keyOf(barcode, symbology);

  /// Whether this row will be written to stock as it stands.
  ///
  /// A pending row is not, and it is not unmatched either: it is a question still out. Folding the two
  /// together would put a row still being looked up into the count of barcodes that could not be
  /// matched, which is a claim about a lookup that has not failed.
  bool get isSettled => !pending && source != ScanSource.unmatched;

  /// Whether this row is waiting on the user before it can be written.
  bool get needsUser => !pending && source == ScanSource.unmatched;

  /// Whether the user should be shown this row's card now.
  ///
  /// **One predicate for two cases that look different and are the same.** A code nothing knew has to
  /// be typed in, and a code only the shared catalogue knew has to be confirmed; both end in a product
  /// being CREATED in this tenant's inventory off the back of something they have not seen. A product
  /// they already own is the third case and asks nothing, which is what [productId] being present
  /// means here.
  bool get needsAsking => !pending && !asked && productId == null;

  /// The same row, with what the user typed into the draft sheet.
  ///
  /// **The source becomes `own`, and that is not a lie about ownership.** `ScanSource` says how far to
  /// trust the answer, not which table it came from: this one came from the person holding the
  /// carton, which is the most authoritative source there is and the one `ScanRow` prints no
  /// provenance for. `recalled` was the alternative and it means specifically a PAST answer of theirs
  /// replayed, which this is not.
  ///
  /// **`productId` is CARRIED, and dropping it was a defect worth recording.** The first version set
  /// it to null so every filled row committed as a card to create. For a catalogue row that is right
  /// and is the whole feature. For a row the tenant already OWNS it is a guaranteed 422: the barcode
  /// is already linked to their product, and `BarcodeLinker` refuses a second one by design. So the
  /// sheet does not offer to rename an owned product, and this keeps the id that makes the commit
  /// send an id.
  ScanEntry filled({
    required String name,
    required String unit,
    String? brand,
    bool contribute = true,
  }) => ScanEntry(
    barcode: barcode,
    symbology: symbology,
    count: count,
    sequence: sequence,
    productName: name,
    source: ScanSource.own,
    productId: productId,
    unit: unit,
    brand: brand,
    contribute: contribute,
    // The card has been seen, so a repeat read of the same carton increments this row silently
    // instead of asking the same question again.
    asked: true,
  );

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
    String? brand,
    bool? contribute,
    bool? pending,
    bool? asked,
  }) => ScanEntry(
    barcode: barcode,
    symbology: symbology,
    sequence: sequence ?? this.sequence,
    productName: productName ?? this.productName,
    source: source ?? this.source,
    count: count ?? this.count,
    productId: productId ?? this.productId,
    unit: unit ?? this.unit,
    brand: brand ?? this.brand,
    contribute: contribute ?? this.contribute,
    pending: pending ?? this.pending,
    asked: asked ?? this.asked,
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
