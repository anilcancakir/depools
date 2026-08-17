import 'package:flutter/foundation.dart';

import '../../resources/views/products/product_fixtures.dart';
import '../../ui/components/receipt_line_row/receipt_line_row.dart';

/// Which step of the resolution cascade produced a `matched` or `created` line.
///
/// `receipt_lines.resolved_by`'s own vocabulary, closed by a `CHECK` on the server. Null covers two
/// different things on purpose: an `unresolved`/`rejected` line that never reached a cascade step, and
/// a string this client does not recognise. A step it cannot name is not one it should claim happened,
/// so an unknown value is read the same as "no step ran" rather than guessed at.
enum ReceiptResolvedBy {
  /// D89's alias table: a printed string the tenant has confirmed before.
  alias,

  /// Matched one of the tenant's own products directly.
  ownProduct,

  /// Matched a row in the shared catalogue.
  catalog,

  /// Matched via Open Food Facts.
  off,

  /// Matched by embedding similarity.
  embedding,

  /// Matched by the AI gateway's judgement.
  model,

  /// Confirmed by the user rather than by any automated step.
  manual,
}

/// One line off a receipt: what the paper said, and what it resolved to.
///
/// Mirrors `ReceiptLineResource` field for field. See `receipt_line_row.dart:10-22` for
/// [LineResolution], reused rather than redeclared here so the mapper and the row it feeds share one
/// vocabulary.
@immutable
class ReceiptLine {
  /// Position on the paper, preserved so a reordered review list can put itself back.
  final int lineNumber;

  /// Exactly as printed. Always shown, even after resolution, because it is the one thing the user
  /// can check against the paper in their hand.
  final String rawName;

  /// How many, or null on a line the extraction could not read a quantity off.
  final num? quantity;

  /// The UN/ECE Rec 20 code as the document gave it, unmapped.
  final String? rawUnitCode;

  /// What the server's unit map made of [rawUnitCode]. Null means unrecognised (D97), a state the
  /// review screen shows rather than a default it hides: guessing a unit changes what every quantity
  /// in the ledger means.
  final String? resolvedUnit;

  final num? unitPrice;

  final num? lineTotal;

  /// How far this line got.
  final LineResolution resolution;

  /// Which cascade step resolved it, or null before resolution or on an unrecognised value.
  final ReceiptResolvedBy? resolvedBy;

  /// The product this line resolved to. Null while [resolution] is unresolved or rejected.
  final String? productId;

  /// The resolved product's name, kept separate from [productId] because an id cannot be rendered.
  ///
  /// Present-and-null for an unresolved line, and absent entirely (also read as null through the
  /// nullable cast below) when the server did not load the relation at all, which is every line on
  /// the list endpoint. Both are the normal state of this slice: nothing has been extracted yet.
  final String? productName;

  /// 0 to 100, never shown as a number (D31): a state the user can act on, not arithmetic.
  final int? confidence;

  final DateTime? confirmedAt;

  /// Creates a [ReceiptLine].
  const ReceiptLine({
    required this.lineNumber,
    required this.rawName,
    required this.resolution,
    this.quantity,
    this.rawUnitCode,
    this.resolvedUnit,
    this.unitPrice,
    this.lineTotal,
    this.resolvedBy,
    this.productId,
    this.productName,
    this.confidence,
    this.confirmedAt,
  });

  /// Builds a line from a `ReceiptLineResource` element.
  factory ReceiptLine.fromApi(Map<String, dynamic> json) {
    return ReceiptLine(
      lineNumber: json['line_number'] as int,
      rawName: json['raw_name'] as String,
      quantity: ProductListItem.toNumOrNull(json['quantity']),
      rawUnitCode: json['raw_unit_code'] as String?,
      resolvedUnit: json['resolved_unit'] as String?,
      unitPrice: ProductListItem.toNumOrNull(json['unit_price']),
      lineTotal: ProductListItem.toNumOrNull(json['line_total']),
      resolution: _resolutionFrom(json['resolution']),
      resolvedBy: _resolvedByFrom(json['resolved_by']),
      productId: json['product_id'] as String?,
      productName: json['product_name'] as String?,
      confidence: json['confidence'] as int?,
      confirmedAt: ProductListItem.parseDate(json['confirmed_at']),
    );
  }

  /// The resolution code, or the safest reading of an unknown one.
  ///
  /// An unrecognised value lands on `unresolved`, the state that claims the least: it says the line
  /// still needs the user rather than claiming it was matched, created or rejected on their behalf.
  static LineResolution _resolutionFrom(Object? value) => switch (value) {
    'matched' => LineResolution.matched,
    'created' => LineResolution.created,
    'rejected' => LineResolution.rejected,
    _ => LineResolution.unresolved,
  };

  /// The cascade step, or null for an unrecognised or absent one.
  static ReceiptResolvedBy? _resolvedByFrom(Object? value) => switch (value) {
    'alias' => ReceiptResolvedBy.alias,
    'own_product' => ReceiptResolvedBy.ownProduct,
    'catalog' => ReceiptResolvedBy.catalog,
    'off' => ReceiptResolvedBy.off,
    'embedding' => ReceiptResolvedBy.embedding,
    'model' => ReceiptResolvedBy.model,
    'manual' => ReceiptResolvedBy.manual,
    _ => null,
  };
}

/// One captured purchase document, as `api/v1/receipts` and `api/v1/receipts/{id}` send it.
///
/// **Every extracted field is null on this slice's receipts, and that is the normal state.** There
/// is no AI extraction wired up yet, so [issuedOn], [totalAmount], [currency] and [supplierName]
/// travel as null on every row. This model carries them anyway because slice 2 fills the same fields
/// rather than adding new ones.
///
/// **There is no `documentUrl` field, deliberately.** The API never sends one on this slice (see
/// `ReceiptResource`'s own docblock): the document sits on a private disk with no route serving it
/// yet, and a nullable field the server never populates would read as "no document" instead of "not
/// implemented". Slice 2 adds the field and the route together.
@immutable
class Receipt {
  final String id;

  /// `fis` on every row this slice can produce; the CHECK on the server refuses anything else on
  /// the photograph path.
  final String kind;

  /// `pending`, `matched`, `confirmed`, ... `data-model.md`'s own vocabulary, kept as a plain string
  /// because nothing in this slice branches on it beyond display.
  final String status;

  final DateTime? issuedOn;

  final num? totalAmount;

  final String? currency;

  final String? supplierName;

  final DateTime? confirmedAt;

  final DateTime? createdAt;

  /// How many lines this receipt has, from the LIST endpoint's `withCount`. Null on the detail
  /// endpoint, where [lines] itself is the answer instead.
  final int? linesCount;

  /// This receipt's lines, in printed order. Empty on the list endpoint, which does not load the
  /// relation at all (see `ReceiptResource`'s `whenLoaded` gate), and on a freshly photographed
  /// receipt regardless of endpoint, since nothing has been extracted yet.
  final List<ReceiptLine> lines;

  /// Creates a [Receipt].
  const Receipt({
    required this.id,
    required this.kind,
    required this.status,
    this.issuedOn,
    this.totalAmount,
    this.currency,
    this.supplierName,
    this.confirmedAt,
    this.createdAt,
    this.linesCount,
    this.lines = const <ReceiptLine>[],
  });

  /// Builds a receipt from a `ReceiptResource` payload.
  factory Receipt.fromApi(Map<String, dynamic> json) {
    return Receipt(
      id: json['id'] as String,
      kind: json['kind'] as String,
      status: json['status'] as String,
      issuedOn: ProductListItem.parseDate(json['issued_on']),
      totalAmount: ProductListItem.toNumOrNull(json['total_amount']),
      currency: json['currency'] as String?,
      supplierName: json['supplier_name'] as String?,
      confirmedAt: ProductListItem.parseDate(json['confirmed_at']),
      createdAt: ProductListItem.parseDate(json['created_at']),
      linesCount: json['lines_count'] as int?,
      lines: _readLines(json['lines']),
    );
  }

  /// The lines of a payload, skipping any row that cannot be drawn.
  ///
  /// Absent entirely on the list endpoint (`whenLoaded` drops the key, not just its value), which
  /// `is! List` catches the same way it catches a payload that sent `null`.
  static List<ReceiptLine> _readLines(Object? value) {
    if (value is! List) return const <ReceiptLine>[];

    return <ReceiptLine>[
      for (final dynamic row in value)
        if (row is Map<dynamic, dynamic>) ReceiptLine.fromApi(Map<String, dynamic>.from(row)),
    ];
  }
}
