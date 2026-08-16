import 'package:flutter/foundation.dart';
import 'package:magic/magic.dart';

import '../../resources/views/products/product_fixtures.dart';
import '../../ui/components/shopping_row/shopping_row.dart';
import '../support/plural.dart';
import '../support/unit_label.dart';

/// One line of the shopping list, as `api/v1/shopping` sends it.
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
@immutable
class ShoppingLine {
  /// The line's own id, which every mutation addresses.
  final String id;

  /// The product this line is about, or null for something typed that is not in the catalogue.
  final String? productId;

  /// What to buy. Always present, even with a product (D100), so the line survives a deletion.
  final String name;

  /// How many, in the base unit.
  final num quantity;

  /// The unit, already resolved by the server.
  final String unit;

  /// Why the line is here.
  final ShoppingReason reason;

  /// The day figure behind the reason, where the tier allows one at all.
  ///
  /// Null is the normal case and it is the gate rather than a gap: only a forecast-backed or a
  /// date-backed line has a number, which a CHECK constraint enforces on the way in.
  final int? days;

  /// The middle tier's bucket, as a code.
  ///
  /// `days`, `week`, `fortnight`, `month` or `rare`, and null on every other tier. It exists
  /// because two to nine observations cannot carry a figure and the day column is closed to this
  /// tier by a CHECK, so without a code the sentence would collapse to "little history" and lose
  /// the half `forecasting.md` specifies. A code cannot be misread as a measurement, which is the
  /// property the figure fails.
  final String? bucket;

  /// How much was on hand when the line was generated.
  final num? onHand;

  /// Whether an expiring line's date is the OPENED clock rather than the printed one (D27).
  ///
  /// Null on every other reason. An opened pot with three days left and a sealed carton with three
  /// days left are two different sentences, and saying the wrong one reads as the app being wrong
  /// about the box.
  final bool? lotIsOpen;

  /// The target that was in force when the line was generated.
  final num? target;

  /// How many DAYS demand happened, which is what the certainty tier was decided on.
  final int movementCount;

  /// Whether the thing is in the trolley. Not stock (D47).
  final bool isChecked;

  /// Creates a [ShoppingLine].
  const ShoppingLine({
    required this.id,
    required this.name,
    required this.quantity,
    required this.unit,
    required this.reason,
    this.productId,
    this.days,
    this.bucket,
    this.onHand,
    this.lotIsOpen,
    this.target,
    this.movementCount = 0,
    this.isChecked = false,
  });

  /// Builds a line from an `api/v1/shopping` element.
  factory ShoppingLine.fromApi(Map<String, dynamic> json) {
    return ShoppingLine(
      id: json['id'] as String,
      productId: json['product_id'] as String?,
      name: json['name'] as String,
      quantity: ProductListItem.toNumOrNull(json['quantity']) ?? 1,
      unit: json['unit'] as String? ?? 'C62',
      reason: _reasonFrom(json['reason']),
      days: json['reason_days'] as int?,
      bucket: json['reason_bucket'] as String?,
      onHand: ProductListItem.toNumOrNull(json['reason_on_hand']),
      lotIsOpen: json['reason_lot_is_open'] as bool?,
      target: ProductListItem.toNumOrNull(json['reason_target']),
      movementCount: json['reason_movement_count'] as int? ?? 0,
      // A timestamp on the wire and a flag here: WHEN it went in the trolley is what a receipt
      // reconciles against, and the screen only ever asks whether it did.
      isChecked: json['checked_at'] != null,
    );
  }

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

  /// A copy with the tick flipped, for the optimistic update.
  ShoppingLine toggled() => ShoppingLine(
    id: id,
    productId: productId,
    name: name,
    quantity: quantity,
    unit: unit,
    reason: reason,
    days: days,
    bucket: bucket,
    onHand: onHand,
    lotIsOpen: lotIsOpen,
    target: target,
    movementCount: movementCount,
    isChecked: !isChecked,
  );
}
