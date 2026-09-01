import 'package:flutter/foundation.dart';

import '../../ui/components/receipt_line_row/receipt_line_row.dart' show LineResolution;

/// One region a shelf photograph produced, and what the app made of it.
///
/// **It lived in `shelf_fixtures.dart` while the screen was drawn against fixtures**, and it moved
/// here rather than being copied, because `flutter-app.md` is explicit: replace the fixture, do not
/// shadow it. Two types for one thing diverge the moment the API changes.
///
/// Two fields went with the move. `formatted` and `meta` were already-presented strings, which a
/// fixture can carry because nothing computes them; a live screen has to, so the view formats the
/// quantity through `ProductListItem.format` and derives the meta line from [resolution], the same
/// way `ReceiptReviewView` does for a receipt line.
@immutable
class ShelfCandidate {
  /// The server's id for this region, which is what a commit decision is keyed against.
  ///
  /// Null only for a fixture: the preview catalog builds these without a backend, and nothing it
  /// renders needs an id.
  final String? id;

  /// The region's number, drawn on the photograph and repeated on its row (D60).
  final int region;

  /// Where the box sits, as fractions of the photo's width and height. Fractions rather than pixels
  /// because the same photo renders at three widths in this app.
  final double left;
  final double top;
  final double width;
  final double height;

  /// What the app read. Null when it read nothing, which `ai-enrichment.md` requires be presented
  /// rather than invented.
  final String? productName;

  /// The product this resolved to, when the cascade found one.
  final String? productId;

  /// How far the candidate got. Shared with the receipt review, because it is the same concept: an
  /// extracted thing resolving to a product, or failing to.
  final LineResolution resolution;

  /// How many of it were seen, or null when the model could not count them.
  ///
  /// **Nullable, and printing `0` for it would be a lie**, the same one `ReceiptReviewView` names: a
  /// row reading "0" claims the shelf held none rather than that the app could not tell.
  final num? quantity;

  /// A Rec 20 code, or null when the label named no unit we recognise.
  final String? unit;

  /// Creates a [ShelfCandidate].
  const ShelfCandidate({
    required this.region,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    this.id,
    this.productName,
    this.productId,
    this.resolution = LineResolution.matched,
    this.quantity,
    this.unit,
  });

  /// The candidate a `shelf-reads` payload describes.
  factory ShelfCandidate.fromApi(Map<String, dynamic> json) {
    return ShelfCandidate(
      id: json['id'] as String?,
      region: (json['region'] as num?)?.toInt() ?? 0,
      left: _fraction(json['left']),
      top: _fraction(json['top']),
      width: _fraction(json['width']),
      height: _fraction(json['height']),
      productName: json['product_name'] as String?,
      productId: json['product_id'] as String?,
      resolution: _resolution(json['resolution'] as String?),
      // A decimal STRING on the wire, because it reaches the ledger and PostgreSQL sends
      // `'3.000'`. Parsed here rather than cast, so a null stays a null.
      quantity: num.tryParse('${json['quantity']}'),
      unit: json['unit'] as String?,
    );
  }

  /// Whether this candidate will be written as it stands.
  bool get isSettled =>
      resolution == LineResolution.matched || resolution == LineResolution.created;

  /// Whether the app read nothing for this region.
  bool get isUnresolved => resolution == LineResolution.unresolved;

  /// The same candidate with the user's decision applied.
  ShelfCandidate accepted({required String productId, required num quantity}) {
    return ShelfCandidate(
      id: id,
      region: region,
      left: left,
      top: top,
      width: width,
      height: height,
      productName: productName,
      productId: productId,
      resolution: LineResolution.matched,
      quantity: quantity,
      unit: unit,
    );
  }

  /// The same candidate marked as not a product.
  ShelfCandidate get rejected => ShelfCandidate(
    id: id,
    region: region,
    left: left,
    top: top,
    width: width,
    height: height,
    productName: productName,
    resolution: LineResolution.rejected,
    quantity: quantity,
    unit: unit,
  );

  /// The four box fields are fractions, so anything outside 0 to 1 is not one.
  ///
  /// The server refuses an out-of-frame box before it is stored and the column rounds to four
  /// decimals, so this is a parser's guard rather than a second rule: a value that arrives broken
  /// would otherwise place a `Positioned` child off the picture and take the whole `Stack` with it.
  static double _fraction(Object? value) {
    final double parsed = value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

    return parsed.clamp(0, 1);
  }

  static LineResolution _resolution(String? value) => switch (value) {
    'matched' => LineResolution.matched,
    'created' => LineResolution.created,
    'rejected' => LineResolution.rejected,
    _ => LineResolution.unresolved,
  };
}

/// One photograph of a shelf and the review it is waiting for.
@immutable
class ShelfRead {
  /// The server's id, which the read and the commit are addressed to.
  final String id;

  /// Whether the review has been finished.
  final bool isConfirmed;

  /// Whether the photograph is still on the server to draw boxes on.
  ///
  /// False once D94's retention window closes. The screen's whole design rests on the picture
  /// staying (D60), so a read that has lost it is a different thing to render.
  final bool hasDocument;

  /// The regions, in the order their numbers read.
  final List<ShelfCandidate> candidates;

  /// The `AiOutcome` the last read attempt ended on, or null when none has run.
  ///
  /// The screen branches on `no_credit`, which is the one the user can act on. Everything else is
  /// "we could not read it", and telling those apart would offer a distinction nobody can use.
  final String? lastReadOutcome;

  /// Creates a [ShelfRead].
  const ShelfRead({
    required this.id,
    this.isConfirmed = false,
    this.hasDocument = true,
    this.candidates = const <ShelfCandidate>[],
    this.lastReadOutcome,
  });

  /// The read a `shelf-reads` payload describes.
  factory ShelfRead.fromApi(Map<String, dynamic> json) {
    final Object? rows = json['candidates'];

    return ShelfRead(
      id: json['id'] as String? ?? '',
      isConfirmed: json['confirmed_at'] != null,
      hasDocument: json['has_document'] as bool? ?? true,
      candidates: rows is! List
          ? const <ShelfCandidate>[]
          : <ShelfCandidate>[
              for (final Object? row in rows)
                if (row is Map<dynamic, dynamic>)
                  ShelfCandidate.fromApi(Map<String, dynamic>.from(row)),
            ],
      lastReadOutcome: json['last_read_outcome'] as String?,
    );
  }

  /// The candidates that would be written as they stand.
  ///
  /// D60 makes this the number the accept button carries, never the region count: six regions
  /// yielded four products in the design, and a button labelled six would promise to write an
  /// unnamed bottle and a price label the recogniser mistook for stock.
  List<ShelfCandidate> get settled =>
      candidates.where((ShelfCandidate c) => c.isSettled).toList(growable: false);

  /// The candidates nothing could name.
  List<ShelfCandidate> get unresolved =>
      candidates.where((ShelfCandidate c) => c.isUnresolved).toList(growable: false);

  /// The same read with one candidate replaced, keyed on its region.
  ShelfRead withCandidate(ShelfCandidate replacement) {
    return ShelfRead(
      id: id,
      isConfirmed: isConfirmed,
      hasDocument: hasDocument,
      candidates: <ShelfCandidate>[
        for (final ShelfCandidate c in candidates)
          if (c.region == replacement.region) replacement else c,
      ],
      lastReadOutcome: lastReadOutcome,
    );
  }
}
