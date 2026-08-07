import 'package:flutter/foundation.dart';

import '../../../ui/components/receipt_line_row/receipt_line_row.dart' show LineResolution;

/// One region a shelf photograph produced, and what the app made of it.
@immutable
class ShelfCandidate {
  /// The region's number, drawn on the photograph and repeated on its row (D60).
  final int region;

  /// Where the box sits, as fractions of the photo's width and height. Fractions rather
  /// than pixels because the same photo renders at three widths in this app.
  final double left;
  final double top;
  final double width;
  final double height;

  /// What the app recognised. Null when it recognised nothing.
  final String? productName;

  /// How far the candidate got. Shared with the receipt review, because it is the same
  /// concept: an extracted thing resolving to a product, or failing to.
  final LineResolution resolution;

  /// The quantity read off the shelf.
  final num amount;

  /// The already-formatted quantity.
  final String formatted;

  /// The unit.
  final String unit;

  /// The already-localised meta line.
  final String? meta;

  /// Creates a [ShelfCandidate].
  const ShelfCandidate({
    required this.region,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.amount,
    required this.formatted,
    this.productName,
    this.resolution = LineResolution.matched,
    this.unit = 'adet',
    this.meta,
  });

  /// Whether this candidate will be written as it stands.
  bool get isSettled =>
      resolution == LineResolution.matched || resolution == LineResolution.created;
}

/// One shelf, six regions, in the state a user reviews.
///
/// **Mixed on purpose, including a failure the model will really make.** Region 6 is a price
/// label the recogniser took for a product; rejecting it is not an edge case, it is Tuesday.
/// Region 3 is a bottle it could not name at all, which `ai-enrichment.md` requires be
/// presented rather than invented.
///
/// The regions are ordered left to right, top to bottom, so the numbers on the photograph read
/// the way a person scans a shelf. That ordering is the only reason the numbers are usable: a
/// list sorted by confidence would put 5 above 2 and the link to the picture would be lost.
const List<ShelfCandidate> shelfCandidates = <ShelfCandidate>[
  ShelfCandidate(
    region: 1,
    left: 0.06,
    top: 0.12,
    width: 0.20,
    height: 0.46,
    productName: 'Pınar Süt Tam Yağlı 1 lt',
    amount: 2,
    formatted: '2',
    meta: 'Envanterinizde',
  ),
  ShelfCandidate(
    region: 2,
    left: 0.30,
    top: 0.16,
    width: 0.16,
    height: 0.38,
    productName: 'Sütaş Ayran 250 ml',
    resolution: LineResolution.created,
    amount: 4,
    formatted: '4',
    meta: 'Yeni ürün · katalogdan',
  ),
  ShelfCandidate(
    region: 3,
    left: 0.50,
    top: 0.10,
    width: 0.14,
    height: 0.50,
    resolution: LineResolution.unresolved,
    amount: 1,
    formatted: '1',
  ),
  ShelfCandidate(
    region: 4,
    left: 0.68,
    top: 0.18,
    width: 0.24,
    height: 0.34,
    productName: 'Yoğurt 2 kg',
    amount: 1,
    formatted: '1',
    meta: 'Envanterinizde',
  ),
  ShelfCandidate(
    region: 5,
    left: 0.10,
    top: 0.64,
    width: 0.18,
    height: 0.28,
    productName: 'Tariş Zeytinyağı 5 lt',
    resolution: LineResolution.created,
    amount: 1,
    formatted: '1',
    meta: 'Yeni ürün · katalogdan',
  ),
  // The model read a shelf label as a product. Rejecting it is routine, so the state has to
  // exist and the row has to stay visible: a candidate that vanished on rejection would be
  // one the user could not un-reject.
  ShelfCandidate(
    region: 6,
    left: 0.34,
    top: 0.70,
    width: 0.22,
    height: 0.16,
    productName: 'Fiyat etiketi',
    resolution: LineResolution.rejected,
    amount: 1,
    formatted: '1',
    meta: 'Atlandı · ürün değil',
  ),
];

/// How many regions the recogniser has finished, in the mid-read state.
const int resolvedSoFar = 4;

/// Candidates that will be written as they stand.
List<ShelfCandidate> get settledCandidates =>
    shelfCandidates.where((c) => c.isSettled).toList(growable: false);

/// Candidates nothing could name.
List<ShelfCandidate> get unresolvedCandidates =>
    shelfCandidates.where((c) => c.resolution == LineResolution.unresolved).toList();
