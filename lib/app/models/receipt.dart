import 'package:magic/magic.dart';

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
///
/// A magic [Model] rather than a value class, sharing this file with [Receipt] because both need to
/// change together. Only [productId] and [quantity] are declared [fillable]: they are the two fields
/// `CommitReceiptRequest`'s `lines.*` actually accepts per line (the product the user confirmed and
/// the quantity as they left it, see `ReceiptController.commit`/`ReceiptLineDecision`). Every other
/// attribute (the raw extraction, the resolution, the confidence) is server-derived and never arrives
/// in a request body.
class ReceiptLine extends Model with InteractsWithPersistence {
  /// The table associated with the model.
  @override
  String get table => 'receipt_lines';

  /// The API resource name. There is no standalone `receipt-lines` endpoint: a line is only ever
  /// written as part of `POST receipts/{receipt}/commit`, so this is never used for a remote
  /// `find`/`save` on its own, but [Model.resource] is not nullable and every model here declares
  /// one.
  @override
  String get resource => 'receipt-lines';

  /// Whether the primary key is auto-incrementing.
  ///
  /// Set to false because this app uses string UUIDs as primary keys.
  @override
  bool get incrementing => false;

  /// The attributes that are mass assignable. See this class's own docblock for why the set is
  /// this narrow.
  @override
  List<String> get fillable => <String>['product_id', 'quantity'];

  /// The attributes that should be cast.
  @override
  Map<String, String> get casts => {};

  // ---------------------------------------------------------------------------
  // Typed Accessors
  // ---------------------------------------------------------------------------

  /// The row's own id, which is how a commit addresses it.
  ///
  /// Position is not an address: a re-extraction renumbers, and the commit keys its idempotency per
  /// line, so a retry after a dropped connection has to name the same line rather than the same
  /// slot.
  @override
  String get id => get<String>('id') ?? '';

  /// Position on the paper, preserved so a reordered review list can put itself back.
  int get lineNumber => get<int>('line_number') ?? 0;

  /// Exactly as printed. Always shown, even after resolution, because it is the one thing the user
  /// can check against the paper in their hand.
  String get rawName => get<String>('raw_name') ?? '';

  /// How many, or null on a line the extraction could not read a quantity off.
  num? get quantity => ProductListItem.toNumOrNull(getAttribute('quantity'));

  /// The UN/ECE Rec 20 code as the document gave it, unmapped.
  String? get rawUnitCode => get<String>('raw_unit_code');

  /// What the server's unit map made of [rawUnitCode]. Null means unrecognised (D97), a state the
  /// review screen shows rather than a default it hides: guessing a unit changes what every quantity
  /// in the ledger means.
  String? get resolvedUnit => get<String>('resolved_unit');

  num? get unitPrice => ProductListItem.toNumOrNull(getAttribute('unit_price'));

  num? get lineTotal => ProductListItem.toNumOrNull(getAttribute('line_total'));

  /// How far this line got.
  LineResolution get resolution => _resolutionFrom(getAttribute('resolution'));

  /// Which cascade step resolved it, or null before resolution or on an unrecognised value.
  ReceiptResolvedBy? get resolvedBy => _resolvedByFrom(getAttribute('resolved_by'));

  /// The product this line resolved to. Null while [resolution] is unresolved or rejected.
  String? get productId => get<String>('product_id');

  /// The resolved product's name, kept separate from [productId] because an id cannot be rendered.
  ///
  /// Present-and-null for an unresolved line, and absent entirely (also read as null through the
  /// nullable read above) when the server did not load the relation at all, which is every line on
  /// the list endpoint. Both are the normal state of this slice: nothing has been extracted yet.
  String? get productName => get<String>('product_name');

  /// 0 to 100, never shown as a number (D31): a state the user can act on, not arithmetic.
  int? get confidence => get<int>('confidence');

  DateTime? get confirmedAt => ProductListItem.parseDate(getAttribute('confirmed_at'));

  // ---------------------------------------------------------------------------
  // Construction
  // ---------------------------------------------------------------------------

  /// An unfilled line, for `..fill(validated, strict: true)` on a write, and the zero-argument
  /// shape [Receipt.relations] needs to decode a nested `lines` payload.
  ///
  /// **Declared explicitly, not left implicit.** Once a class declares any other constructor
  /// (`_raw`, `of`), Dart stops auto-generating the plain unnamed one.
  ReceiptLine();

  /// Builds a line from a `ReceiptLineResource` element.
  static ReceiptLine fromApi(Map<String, dynamic> json) => ReceiptLine._raw(json);

  /// Builds a line from already-known fields, for a fixture or a test.
  ///
  /// Bypasses [fillable] the way `User.fromMap` does: this is not the mass-assignment path, it is
  /// hydration from data the caller already trusts.
  factory ReceiptLine.of({
    required String id,
    required int lineNumber,
    required String rawName,
    required LineResolution resolution,
    num? quantity,
    String? rawUnitCode,
    String? resolvedUnit,
    num? unitPrice,
    num? lineTotal,
    ReceiptResolvedBy? resolvedBy,
    String? productId,
    String? productName,
    int? confidence,
    DateTime? confirmedAt,
  }) {
    return ReceiptLine._raw(<String, dynamic>{
      'id': id,
      'line_number': lineNumber,
      'raw_name': rawName,
      'quantity': quantity,
      'raw_unit_code': rawUnitCode,
      'resolved_unit': resolvedUnit,
      'unit_price': unitPrice,
      'line_total': lineTotal,
      'resolution': _resolutionToApi(resolution),
      'resolved_by': _resolvedByToApi(resolvedBy),
      'product_id': productId,
      'product_name': productName,
      'confidence': confidence,
      'confirmed_at': confirmedAt?.toIso8601String(),
    });
  }

  ReceiptLine._raw(Map<String, dynamic> attributes) {
    setRawAttributes(attributes, sync: true);
    exists = true;
  }

  // ---------------------------------------------------------------------------
  // Behaviour
  // ---------------------------------------------------------------------------

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

  /// The wire code for a resolution, the inverse of [_resolutionFrom].
  static String _resolutionToApi(LineResolution value) => switch (value) {
    LineResolution.matched => 'matched',
    LineResolution.created => 'created',
    LineResolution.rejected => 'rejected',
    LineResolution.unresolved => 'unresolved',
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

  /// The wire code for a cascade step, the inverse of [_resolvedByFrom].
  static String? _resolvedByToApi(ReceiptResolvedBy? value) => switch (value) {
    null => null,
    ReceiptResolvedBy.alias => 'alias',
    ReceiptResolvedBy.ownProduct => 'own_product',
    ReceiptResolvedBy.catalog => 'catalog',
    ReceiptResolvedBy.off => 'off',
    ReceiptResolvedBy.embedding => 'embedding',
    ReceiptResolvedBy.model => 'model',
    ReceiptResolvedBy.manual => 'manual',
  };
}

/// One captured purchase document, as `api/v1/receipts` and `api/v1/receipts/{id}` send it.
///
/// A magic [Model] rather than a value class. [fillable] is deliberately empty: `StoreReceiptRequest`
/// validates only the multipart `image` field, never a JSON attribute of the receipt itself, and
/// `extract`/`commit` are server-driven actions rather than a field-level write (see
/// `ReceiptController`). Empty rather than invented, so the mass-assignment guard here still means
/// something the day a receipt field becomes client-editable, instead of a fillable list padded with
/// fields nothing writes.
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
class Receipt extends Model with InteractsWithPersistence {
  /// The table associated with the model.
  @override
  String get table => 'receipts';

  /// The API resource for remote operations.
  @override
  String get resource => 'receipts';

  /// Whether the primary key is auto-incrementing.
  ///
  /// Set to false because this app uses string UUIDs as primary keys.
  @override
  bool get incrementing => false;

  /// The attributes that are mass assignable. See this class's own docblock for why it is empty.
  @override
  List<String> get fillable => const <String>[];

  /// The attributes that should be cast.
  @override
  Map<String, String> get casts => {};

  /// `lines` casts from a nested `List<Map>` to [ReceiptLine], the way [Model.relations] is meant to
  /// be used: the API nests the lines on the detail endpoint and omits the key entirely on the list
  /// endpoint (`whenLoaded`), so there is nothing here to load lazily.
  @override
  Map<String, Model Function()> get relations => <String, Model Function()>{
    'lines': ReceiptLine.new,
  };

  // ---------------------------------------------------------------------------
  // Typed Accessors
  // ---------------------------------------------------------------------------

  @override
  String get id => get<String>('id') ?? '';

  /// `fis` on every row this slice can produce; the CHECK on the server refuses anything else on
  /// the photograph path.
  String get kind => get<String>('kind') ?? 'fis';

  /// `pending`, `matched`, `confirmed`, ... `data-model.md`'s own vocabulary, kept as a plain string
  /// because nothing in this slice branches on it beyond display.
  String get status => get<String>('status') ?? 'pending';

  DateTime? get issuedOn => ProductListItem.parseDate(getAttribute('issued_on'));

  num? get totalAmount => ProductListItem.toNumOrNull(getAttribute('total_amount'));

  String? get currency => get<String>('currency');

  String? get supplierName => get<String>('supplier_name');

  DateTime? get confirmedAt => ProductListItem.parseDate(getAttribute('confirmed_at'));

  DateTime? get createdAt => ProductListItem.parseDate(getAttribute('created_at'));

  /// How many lines this receipt has, from the LIST endpoint's `withCount`. Null on the detail
  /// endpoint, where [lines] itself is the answer instead.
  int? get linesCount => get<int>('lines_count');

  /// Why the last read produced what it produced, or null when nothing has read this receipt.
  ///
  /// A receipt with no lines is three situations wearing one shape: never read, out of AI credits,
  /// or read by a model that could not use what it saw. The screen says something different for each
  /// and cannot tell them apart from an empty list.
  ///
  /// Null also covers a read attempted with the gateway kill switch on, which writes no attempt row.
  /// The screen treats that as "could not read", which is the honest thing to tell somebody who
  /// cannot see the switch.
  String? get lastExtractionOutcome => get<String>('last_extraction_outcome');

  /// This receipt's lines, in printed order. Empty on the list endpoint, which does not load the
  /// relation at all (see `ReceiptResource`'s `whenLoaded` gate), and on a freshly photographed
  /// receipt regardless of endpoint, since nothing has been extracted yet.
  List<ReceiptLine> get lines => getRelations<ReceiptLine>('lines');

  // ---------------------------------------------------------------------------
  // Construction
  // ---------------------------------------------------------------------------

  /// An unfilled receipt, for `..fill(validated, strict: true)` on a write.
  ///
  /// **Declared explicitly, not left implicit.** Once a class declares any other constructor
  /// (`_raw`, `of`), Dart stops auto-generating the plain unnamed one.
  Receipt();

  /// Builds a receipt from a `ReceiptResource` payload.
  static Receipt fromApi(Map<String, dynamic> json) => Receipt._raw(json);

  /// Builds a receipt from already-known fields, for a fixture or a test.
  ///
  /// Bypasses [fillable] the way `User.fromMap` does: this is not the mass-assignment path, it is
  /// hydration from data the caller already trusts. [lines] is stored as already-built [ReceiptLine]
  /// models, which `getRelations` returns as-is (see its own docblock: "already models, assigned not
  /// loaded").
  factory Receipt.of({
    required String id,
    String? lastExtractionOutcome,
    required String kind,
    required String status,
    DateTime? issuedOn,
    num? totalAmount,
    String? currency,
    String? supplierName,
    DateTime? confirmedAt,
    DateTime? createdAt,
    int? linesCount,
    List<ReceiptLine> lines = const <ReceiptLine>[],
  }) {
    return Receipt._raw(<String, dynamic>{
      'id': id,
      'last_extraction_outcome': lastExtractionOutcome,
      'kind': kind,
      'status': status,
      'issued_on': issuedOn?.toIso8601String(),
      'total_amount': totalAmount,
      'currency': currency,
      'supplier_name': supplierName,
      'confirmed_at': confirmedAt?.toIso8601String(),
      'created_at': createdAt?.toIso8601String(),
      'lines_count': linesCount,
      'lines': lines,
    });
  }

  Receipt._raw(Map<String, dynamic> attributes) {
    setRawAttributes(attributes, sync: true);
    exists = true;
  }
}
