import 'package:magic/magic.dart';

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
///
/// **Read-only.** A candidate is written by the server's own commit endpoint; nothing here calls
/// `save()`, so [fillable] stays empty.
class ShelfCandidate extends Model {
  @override
  String get table => 'shelf_candidates';

  @override
  String get resource => 'shelf-reads';

  /// Set to false because this app uses string UUIDs as primary keys.
  @override
  bool get incrementing => false;

  @override
  List<String> get fillable => [];

  @override
  Map<String, dynamic> get casts => <String, dynamic>{
    'region': 'int',
    'left': 'double',
    'top': 'double',
    'width': 'double',
    'height': 'double',
    'resolution': EnumCast(LineResolution.values),
  };

  /// The server's id for this region, which is what a commit decision is keyed against.
  ///
  /// Null only for a fixture: the preview catalog builds these without a backend, and nothing it
  /// renders needs an id.
  @override
  String? get id => get<String>('id');

  /// The region's number, drawn on the photograph and repeated on its row (D60).
  int get region => get<int>('region') ?? 0;

  /// Where the box sits, as fractions of the photo's width and height. Fractions rather than pixels
  /// because the same photo renders at three widths in this app.
  ///
  /// **The four box fields are fractions, so anything outside 0 to 1 is not one.** The server refuses
  /// an out-of-frame box before it is stored and the column rounds to four decimals, so this clamp is
  /// a parser's guard against a nonsense OUTLINE rather than against a crash: a `Positioned` child
  /// whose rect falls outside its `Stack` is clipped, not an error.
  double get left => _fraction(get<double>('left'));
  double get top => _fraction(get<double>('top'));
  double get width => _fraction(get<double>('width'));
  double get height => _fraction(get<double>('height'));

  /// What the app read. Null when it read nothing, which `ai-enrichment.md` requires be presented
  /// rather than invented.
  String? get productName => get<String>('product_name');

  /// The product this resolved to, when the cascade found one.
  String? get productId => get<String>('product_id');

  /// How far the candidate got. Shared with the receipt review, because it is the same concept: an
  /// extracted thing resolving to a product, or failing to.
  ///
  /// Falls back to [LineResolution.unresolved] rather than to `matched`: an unrecognised value would
  /// otherwise silently write stock for a state this build does not understand.
  LineResolution get resolution => get<LineResolution>('resolution') ?? LineResolution.unresolved;

  /// How many of it were seen, or null when the model could not count them.
  ///
  /// **Nullable, and printing `0` for it would be a lie**, the same one `ReceiptReviewView` names: a
  /// row reading "0" claims the shelf held none rather than that the app could not tell.
  ///
  /// Parsed rather than cast: the wire carries a decimal STRING (PostgreSQL sends `'3.000'`), so a
  /// declared numeric cast would leave it a string. Parsed here so a null stays a null.
  num? get quantity {
    final Object? raw = getAttribute('quantity');

    return raw == null ? null : num.tryParse('$raw');
  }

  /// A Rec 20 code, or null when the label named no unit we recognise.
  String? get unit => get<String>('unit');

  /// Whether a movement has already been written for this region.
  ///
  /// **The server skips an answered candidate and answers 200, so without this the screen lies.**
  /// `ShelfCommitter` `continue`s past every row with a `confirmed_at` and the commit endpoint has no
  /// re-commit refusal, so a second submit writes nothing and returns success. A screen that could
  /// not see the column then counted written regions on its accept button and reported them again in
  /// its success message.
  bool get isAnswered => has('confirmed_at');

  /// Whether this candidate will be written as it stands.
  ///
  /// Answered regions are excluded, so the count on the button is what a submit would actually add.
  bool get isSettled =>
      !isAnswered &&
      (resolution == LineResolution.matched || resolution == LineResolution.created);

  /// Whether the commit may carry this region.
  ///
  /// **One predicate rather than two, and the two agreed only by accident.** `isSettled` alone was
  /// on the button while the payload additionally required a product id, which matches today only
  /// because `created` is unwritable: the migration says so and says the catalogue step that starts
  /// writing it "is the next slice". On the day it lands, a button promising N would have carried
  /// N-1 with nothing to notice it.
  bool get isAcceptable => isSettled && productId != null;

  /// Whether the app read nothing for this region.
  bool get isUnresolved => resolution == LineResolution.unresolved;

  /// Creates a [ShelfCandidate] for a fixture or a UI decision, not for hydrating a payload.
  ///
  /// Writes the same wire shape [fromApi] reads (`resolution` stores the enum's own name, and
  /// `confirmed_at` carries a timestamp exactly when [isAnswered] is true), so a getter never has to
  /// ask which path built the instance.
  ShelfCandidate({
    required int region,
    required double left,
    required double top,
    required double width,
    required double height,
    String? id,
    String? productName,
    String? productId,
    LineResolution resolution = LineResolution.matched,
    num? quantity,
    String? unit,
    bool isAnswered = false,
  }) {
    setRawAttributes(<String, dynamic>{
      'id': id,
      'region': region,
      'left': left,
      'top': top,
      'width': width,
      'height': height,
      'product_name': productName,
      'product_id': productId,
      'resolution': resolution.name,
      'quantity': quantity,
      'unit': unit,
      'confirmed_at': isAnswered ? DateTime.now().toIso8601String() : null,
    }, sync: true);
  }

  ShelfCandidate._raw();

  /// The candidate a `shelf-reads` payload describes.
  static ShelfCandidate fromApi(Map<String, dynamic> json) {
    return ShelfCandidate._raw()
      ..setRawAttributes(json, sync: true)
      ..exists = true;
  }

  /// The same candidate with the user's decision applied.
  ///
  /// [unit] is the code a newly created product was given. It is optional because a matched region
  /// already has one and the sheet does not offer to change it (D54 allows that in a draft and
  /// nowhere else); passing it through matters for the other case, where the region had no unit at
  /// all and the row would otherwise render its quantity with nothing beside it.
  ShelfCandidate accepted({
    required String productId,
    required num quantity,
    String? unit,
  }) {
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
      unit: unit ?? this.unit,
      isAnswered: isAnswered,
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
    isAnswered: isAnswered,
  );

  static double _fraction(double? value) => (value ?? 0).clamp(0, 1).toDouble();
}

/// One photograph of a shelf and the review it is waiting for.
///
/// **Read-only.** The read itself is written by `POST /shelf-reads` and its `read`/`commit` actions;
/// nothing here calls `save()`, so [fillable] stays empty.
class ShelfRead extends Model {
  @override
  String get table => 'shelf_reads';

  @override
  String get resource => 'shelf-reads';

  /// Set to false because this app uses string UUIDs as primary keys.
  @override
  bool get incrementing => false;

  @override
  List<String> get fillable => [];

  @override
  Map<String, dynamic> get casts => <String, dynamic>{'has_document': 'bool'};

  /// The nested candidate list. `getRelations` resolves it whether the attribute holds raw maps (a
  /// `shelf-reads` payload) or already-built [ShelfCandidate] instances (a fixture), since it checks
  /// `data is List<T>` before reaching for this factory.
  ///
  /// **`ShelfCandidate._raw`, not `ShelfCandidate.new`.** `getRelations` invokes the factory with no
  /// arguments, and the public constructor's `region`/`left`/`top`/`width`/`height` are required for
  /// the fixture path; the zero-argument private constructor is what a bare hydration needs.
  @override
  Map<String, Model Function()> get relations => <String, Model Function()>{
    'candidates': ShelfCandidate._raw,
  };

  /// The server's id, which the read and the commit are addressed to.
  @override
  String get id => get<String>('id') ?? '';

  /// Whether the review has been finished.
  bool get isConfirmed => has('confirmed_at');

  /// Whether the photograph is still on the server to draw boxes on.
  ///
  /// False once D94's retention window closes. The screen's whole design rests on the picture
  /// staying (D60), so a read that has lost it is a different thing to render.
  bool get hasDocument => get<bool>('has_document') ?? true;

  /// The regions, in the order their numbers read.
  List<ShelfCandidate> get candidates => getRelations<ShelfCandidate>('candidates');

  /// The `AiOutcome` the last read attempt ended on, or null when none has run.
  ///
  /// The screen branches on `no_credit`, which is the one the user can act on. Everything else is
  /// "we could not read it", and telling those apart would offer a distinction nobody can use.
  String? get lastReadOutcome => get<String>('last_read_outcome');

  /// Creates a [ShelfRead] for a fixture or a UI decision, not for hydrating a payload.
  ///
  /// Writes the same wire shape [fromApi] reads (`confirmed_at` carries a timestamp exactly when
  /// [isConfirmed] is true), so a getter never has to ask which path built the instance.
  ShelfRead({
    required String id,
    bool isConfirmed = false,
    bool hasDocument = true,
    List<ShelfCandidate> candidates = const <ShelfCandidate>[],
    String? lastReadOutcome,
  }) {
    setRawAttributes(<String, dynamic>{
      'id': id,
      'confirmed_at': isConfirmed ? DateTime.now().toIso8601String() : null,
      'has_document': hasDocument,
      'candidates': candidates,
      'last_read_outcome': lastReadOutcome,
    }, sync: true);
  }

  ShelfRead._raw();

  /// The read a `shelf-reads` payload describes.
  static ShelfRead fromApi(Map<String, dynamic> json) {
    return ShelfRead._raw()
      ..setRawAttributes(json, sync: true)
      ..exists = true;
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
