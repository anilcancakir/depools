import 'package:magic/magic.dart';

/// One ledger entry, as the API sends it.
///
/// **Nothing here is a sentence.** The reason arrives as its enum value and the actor as a type plus
/// an optional name, so the words come from this app's own catalogues. That is the whole point of
/// the endpoint: the product screen used to render three invented rows in Turkish on an app whose
/// default locale is English, and a server that named the reason in words would have moved the
/// defect rather than fixed it.
///
/// **Read-only, and [fillable] says so.** Stock is a ledger: every change is an append-only row a
/// server endpoint writes, never a client mass-assignment, so nothing here is ever `save()`d.
class MovementEntry extends Model {
  @override
  String get table => 'movements';

  /// The API resource this ledger row belongs to.
  ///
  /// **Nested rather than flat.** There is no top-level `movements` endpoint; every read goes
  /// through `products/{product}/movements` (`backend/routes/api.php:90`), so this names the entity
  /// rather than an addressable path. Nothing here calls `save()` or `findById`, so the mismatch
  /// between this value and the real nested path is never exercised.
  @override
  String get resource => 'movements';

  /// Set to false because this app uses string UUIDs as primary keys.
  @override
  bool get incrementing => false;

  /// Nothing is fillable: the ledger is append-only and a movement is written by an endpoint, never
  /// mass-assigned from this client.
  @override
  List<String> get fillable => [];

  @override
  Map<String, dynamic> get casts => <String, dynamic>{
    'delta': 'double',
    'entered_quantity': 'double',
    'occurred_at': 'datetime',
  };

  /// The reason's enum value (`purchase`, `waste`, `stock_take`, ...).
  String get reason => get<String>('reason') ?? '';

  /// The signed amount, in the product's base unit. Negative takes stock away.
  double get delta => get<double>('delta') ?? 0;

  /// What the person actually typed, when it differs from the base unit (D90).
  ///
  /// A delivery keyed as "2 koli" reads back as "24 adet" without these, which is true and not what
  /// anybody entered.
  double? get enteredQuantity => get<double>('entered_quantity');

  /// The code of the unit they typed it in.
  String? get enteredUnit => get<String>('entered_unit');

  /// `user`, `assistant`, `mcp_client` or `system`.
  String? get actorType => get<String>('actor_type');

  /// The person's own name, when a person did it. Never translated.
  String? get actorName => get<String>('actor_name');

  /// Where it happened, already named.
  String? get locationName => get<String>('location_name');

  /// WHICH product changed, on a feed that spans products.
  ///
  /// Null on a product's own activity card, and correctly so: that card is nested under the product
  /// and the endpoint does not pay for a join to repeat a name already in the header. The dashboard
  /// feed has no such header, so a row without this says only that something moved.
  String? get productName => get<String>('product_name');

  /// When it HAPPENED, which is not when it was written.
  ///
  /// `occurred_at` rather than `created_at`: a receipt entered on Tuesday for a Sunday shop has to
  /// read as Sunday, or the audit trail disagrees with the forecast built on the same rows.
  DateTime? get at => get<Carbon>('occurred_at')?.toDateTime;

  /// Creates a [MovementEntry] for a fixture or a preview, not for hydrating an API payload.
  ///
  /// Writes the same wire shape [fromMap] reads, so a getter never has to ask which path built it.
  MovementEntry({
    required String reason,
    required double delta,
    double? enteredQuantity,
    String? enteredUnit,
    String? actorType,
    String? actorName,
    String? locationName,
    String? productName,
    DateTime? at,
  }) {
    setRawAttributes(<String, dynamic>{
      'reason': reason,
      'delta': delta,
      'entered_quantity': enteredQuantity,
      'entered_unit': enteredUnit,
      'actor_type': actorType,
      'actor_name': actorName,
      'location_name': locationName,
      'product_name': productName,
      'occurred_at': at,
    }, sync: true);
  }

  MovementEntry._raw();

  /// Reads one from the API's shape, or null when it is unreadable.
  ///
  /// Null rather than a throw, so `mappedOrNull` turns a malformed payload into a card that shows
  /// nothing rather than a screen that never finishes loading. The reason and the delta are the two
  /// fields a row cannot be drawn without.
  static MovementEntry? fromMap(Map<String, dynamic> map) {
    final Object? reason = map['reason'];
    final Object? delta = map['delta'];

    if (reason is! String || delta is! num) {
      return null;
    }

    return MovementEntry._raw()
      ..setRawAttributes(map, sync: true)
      ..exists = true;
  }
}
