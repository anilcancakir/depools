import 'package:flutter/foundation.dart';

/// One ledger entry, as the API sends it.
///
/// **Nothing here is a sentence.** The reason arrives as its enum value and the actor as a type plus
/// an optional name, so the words come from this app's own catalogues. That is the whole point of
/// the endpoint: the product screen used to render three invented rows in Turkish on an app whose
/// default locale is English, and a server that named the reason in words would have moved the
/// defect rather than fixed it.
@immutable
class MovementEntry {
  /// The reason's enum value (`purchase`, `waste`, `stock_take`, ...).
  final String reason;

  /// The signed amount, in the product's base unit. Negative takes stock away.
  final double delta;

  /// What the person actually typed, when it differs from the base unit (D90).
  ///
  /// A delivery keyed as "2 koli" reads back as "24 adet" without these, which is true and not what
  /// anybody entered.
  final double? enteredQuantity;

  /// The code of the unit they typed it in.
  final String? enteredUnit;

  /// `user`, `assistant`, `mcp_client` or `system`.
  final String? actorType;

  /// The person's own name, when a person did it. Never translated.
  final String? actorName;

  /// Where it happened, already named.
  final String? locationName;

  /// When, as sent. Parsed by the caller that formats it.
  final DateTime? at;

  /// Creates a [MovementEntry].
  const MovementEntry({
    required this.reason,
    required this.delta,
    this.enteredQuantity,
    this.enteredUnit,
    this.actorType,
    this.actorName,
    this.locationName,
    this.at,
  });

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

    return MovementEntry(
      reason: reason,
      delta: delta.toDouble(),
      enteredQuantity: map['entered_quantity'] is num
          ? (map['entered_quantity'] as num).toDouble()
          : null,
      enteredUnit: map['entered_unit'] is String ? map['entered_unit'] as String : null,
      actorType: map['actor_type'] is String ? map['actor_type'] as String : null,
      actorName: map['actor_name'] is String ? map['actor_name'] as String : null,
      locationName: map['location_name'] is String ? map['location_name'] as String : null,
      at: map['created_at'] is String ? DateTime.tryParse(map['created_at'] as String) : null,
    );
  }
}
