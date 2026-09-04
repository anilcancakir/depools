import 'package:magic/magic.dart';

import '../../resources/views/products/product_fixtures.dart';
import '../../ui/components/shopping_row/shopping_row.dart';
import '../support/plural.dart';
import '../support/unit_label.dart';

/// One line of the shopping list, as `api/v1/shopping` sends it.
///
/// A magic [Model] rather than a value class: `add` writes through [ShoppingController], whose
/// fields mirror `StoreShoppingListItemRequest`/`UpdateShoppingListItemRequest` and are declared
/// in [fillable], so a schema drift between the two rule sets throws `MassAssignmentException`
/// (`fill(..., strict: true)`) instead of silently dropping a field.
///
/// ### The sentence is built HERE, from evidence, and that is D98
///
/// The server sends a reason code and the frozen numbers behind it, never a phrase. A Turkish
/// string in the database would make the English interface untranslatable, because the job that
/// generated the list would have picked a language and a user switching locale would find their
/// list in the old one.
///
/// So [reasonDetail] is the only place a shopping reason becomes words, and it is the enforcement
/// point for D46 as much as the rendering one: a line's SHAPE of sentence is decided by what the
/// payload carries, and a `roughlyDue` line carries no day count at all, so there is nothing a
/// bucket could accidentally be printed as a measurement from.
class ShoppingLine extends Model with InteractsWithPersistence {
  /// The table associated with the model.
  @override
  String get table => 'shopping_list_items';

  /// The API resource for remote operations, matching `api/v1/shopping`.
  @override
  String get resource => 'shopping';

  /// Whether the primary key is auto-incrementing.
  ///
  /// Set to false because this app uses string UUIDs as primary keys.
  @override
  bool get incrementing => false;

  /// The attributes that are mass assignable.
  ///
  /// The union of `StoreShoppingListItemRequest::rules()` and
  /// `UpdateShoppingListItemRequest::rules()`. Every other attribute here (`id`, the `reason_*`
  /// columns, `movement_count`) is server-computed and never arrives in a request body; `team_id`
  /// never appears here either, per this app's own tenancy invariant.
  @override
  List<String> get fillable => <String>['product_id', 'name', 'quantity', 'unit', 'is_checked'];

  /// The attributes that should be cast.
  ///
  /// Empty: `quantity` arrives as a decimal string PostgreSQL sends, which the built-in `double`
  /// cast cannot round-trip without loss the way [quantity]'s own read does through
  /// [ProductListItem.toNumOrNull].
  @override
  Map<String, String> get casts => {};

  // ---------------------------------------------------------------------------
  // Typed Accessors
  // ---------------------------------------------------------------------------

  /// The line's own id, which every mutation addresses.
  @override
  String get id => get<String>('id') ?? '';

  /// The product this line is about, or null for something typed that is not in the catalogue.
  String? get productId => get<String>('product_id');

  /// What to buy. Always present, even with a product (D100), so the line survives a deletion.
  String get name => get<String>('name') ?? '';

  /// How many, in the base unit.
  num get quantity => ProductListItem.toNumOrNull(getAttribute('quantity')) ?? 1;

  /// The unit, already resolved by the server.
  String get unit => get<String>('unit') ?? 'C62';

  /// Why the line is here.
  ShoppingReason get reason => _reasonFrom(getAttribute('reason'));

  /// The day figure behind the reason, where the tier allows one at all.
  ///
  /// Null is the normal case and it is the gate rather than a gap: only a forecast-backed or a
  /// date-backed line has a number, which a CHECK constraint enforces on the way in.
  int? get days => get<int>('reason_days');

  /// The middle tier's bucket, as a code.
  ///
  /// `days`, `week`, `fortnight`, `month` or `rare`, and null on every other tier. It exists
  /// because two to nine observations cannot carry a figure and the day column is closed to this
  /// tier by a CHECK, so without a code the sentence would collapse to "little history" and lose
  /// the half `forecasting.md` specifies. A code cannot be misread as a measurement, which is the
  /// property the figure fails.
  String? get bucket => get<String>('reason_bucket');

  /// How much was on hand when the line was generated.
  num? get onHand => ProductListItem.toNumOrNull(getAttribute('reason_on_hand'));

  /// Whether an expiring line's date is the OPENED clock rather than the printed one (D27).
  ///
  /// Null on every other reason. An opened pot with three days left and a sealed carton with three
  /// days left are two different sentences, and saying the wrong one reads as the app being wrong
  /// about the box.
  bool? get lotIsOpen => get<bool>('reason_lot_is_open');

  /// The target that was in force when the line was generated.
  num? get target => ProductListItem.toNumOrNull(getAttribute('reason_target'));

  /// How many DAYS demand happened, which is what the certainty tier was decided on.
  int get movementCount => get<int>('reason_movement_count') ?? 0;

  /// Whether the thing is in the trolley. Not stock (D47).
  ///
  /// A timestamp on the wire and a flag here: WHEN it went in the trolley is what a receipt
  /// reconciles against, and the screen only ever asks whether it did.
  bool get isChecked => getAttribute('checked_at') != null;

  // ---------------------------------------------------------------------------
  // Construction
  // ---------------------------------------------------------------------------

  /// An unfilled line, for `..fill(validated, strict: true)` on a write.
  ///
  /// **Declared explicitly, not left implicit.** Once a class declares any other constructor
  /// (`_raw`, `of`), Dart stops auto-generating the plain unnamed one; a controller's write path
  /// needs it as the starting point for a mass-assignment guarded fill.
  ShoppingLine();

  /// Builds a line from an `api/v1/shopping` element.
  static ShoppingLine fromApi(Map<String, dynamic> json) => ShoppingLine._raw(json);

  /// Builds a line from already-known fields, for a fixture or a test.
  ///
  /// Bypasses [fillable] the way `User.fromMap` does: this is not the mass-assignment path, it is
  /// hydration from data the caller already trusts.
  factory ShoppingLine.of({
    required String id,
    required String name,
    required num quantity,
    required String unit,
    required ShoppingReason reason,
    String? productId,
    int? days,
    String? bucket,
    num? onHand,
    bool? lotIsOpen,
    num? target,
    int movementCount = 0,
    bool isChecked = false,
  }) {
    return ShoppingLine._raw(<String, dynamic>{
      'id': id,
      'product_id': productId,
      'name': name,
      'quantity': quantity,
      'unit': unit,
      'reason': _reasonToApi(reason),
      'reason_days': days,
      'reason_bucket': bucket,
      'reason_on_hand': onHand,
      'reason_lot_is_open': lotIsOpen,
      'reason_target': target,
      'reason_movement_count': movementCount,
      'checked_at': isChecked ? DateTime.now().toIso8601String() : null,
    });
  }

  ShoppingLine._raw(Map<String, dynamic> attributes) {
    setRawAttributes(attributes, sync: true);
    exists = true;
  }

  // ---------------------------------------------------------------------------
  // Behaviour
  // ---------------------------------------------------------------------------

  /// The already-formatted quantity for the row.
  String get formatted => ProductListItem.format(quantity);

  /// Why this line is here, in words.
  ///
  /// **Each branch may only claim what its evidence supports** (D46). Ten or more demand days earns
  /// a number, two to nine earns a bucket and never a number at any precision, and below that a
  /// bare ratio with no time in it. The server has already decided which by choosing the reason and
  /// by sending or withholding [days]; this reads that decision rather than making a second one.
  String get reasonDetail => switch (reason) {
    // Zero on hand says so instead of stating a cover figure. "2 days left" beside a quantity of
    // nothing is a forecast contradicting the number next to it.
    ShoppingReason.runningOut when days == null => Lang.get('screens.shopping.reason_out'),
    ShoppingReason.runningOut => plural('screens.shopping.reason_cover', days!, {'days': days}),
    ShoppingReason.roughlyDue => Lang.get(_roughKey),
    ShoppingReason.expiring when days == 0 => Lang.get('screens.shopping.reason_expiring_today'),
    ShoppingReason.expiring => plural(
      // An opened pot runs on the after-opening limit rather than the printed date (D27), and the
      // sentence says which: "3 days left" about a carton with a week on the box would read as the
      // app being wrong rather than as the pot being open.
      lotIsOpen == true
          ? 'screens.shopping.reason_expiring_open'
          : 'screens.shopping.reason_expiring',
      days!,
      {'days': days},
    ),
    ShoppingReason.belowTarget => Lang.get('screens.shopping.reason_target', {
      'on': onHand ?? 0,
      'par': target ?? 0,
      'unit': unitLabel(unit, target ?? 1),
    }),
    ShoppingReason.manual => Lang.get('screens.shopping.reason_manual'),
  };

  /// The copy key for a rough line's bucket.
  ///
  /// The BOUNDARIES are the server's, deliberately: putting them here would be a second place for
  /// "about weekly" to be defined, and the two would disagree the first time either was tuned. This
  /// maps a code to a string and nothing else, so an unknown code degrades to saying only that the
  /// history is thin, which is true whatever the interval turns out to be.
  String get _roughKey => switch (bucket) {
    'days' => 'screens.shopping.reason_rough_days',
    'week' => 'screens.shopping.reason_rough_week',
    'fortnight' => 'screens.shopping.reason_rough_fortnight',
    'month' => 'screens.shopping.reason_rough_month',
    'rare' => 'screens.shopping.reason_rough_rare',
    _ => 'screens.shopping.reason_rough_unknown',
  };

  /// The reason code, or the safest reading of an unknown one.
  ///
  /// An unrecognised value lands on `manual`, which claims nothing at all. The vocabulary is closed
  /// by a CHECK so a sixth value cannot arrive from this server, and the failure direction still has
  /// to be the safe one: a line that over-claims is the failure this whole feature is built around.
  static ShoppingReason _reasonFrom(Object? value) => switch (value) {
    'running_out' => ShoppingReason.runningOut,
    'roughly_due' => ShoppingReason.roughlyDue,
    'below_target' => ShoppingReason.belowTarget,
    'expiring' => ShoppingReason.expiring,
    _ => ShoppingReason.manual,
  };

  /// The wire code for a reason, the inverse of [_reasonFrom], for [ShoppingLine.of].
  static String _reasonToApi(ShoppingReason reason) => switch (reason) {
    ShoppingReason.runningOut => 'running_out',
    ShoppingReason.roughlyDue => 'roughly_due',
    ShoppingReason.belowTarget => 'below_target',
    ShoppingReason.expiring => 'expiring',
    ShoppingReason.manual => 'manual',
  };

  /// A copy with the tick flipped, for the optimistic update.
  ShoppingLine toggled() {
    final Map<String, dynamic> next = Map<String, dynamic>.from(attributes);
    next['checked_at'] = isChecked ? null : DateTime.now().toIso8601String();

    return ShoppingLine._raw(next);
  }
}
