import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import 'movement_row.recipe.dart';

/// Which way a movement pushed stock, which decides its tint and icon.
enum MovementDirection {
  /// Stock came in: a purchase, a transfer in, a return from a customer.
  inbound,

  /// Stock went out through normal use: consumption, a sale, a transfer out.
  outbound,

  /// Stock was discarded: spoiled, broken, expired.
  ///
  /// Its own direction rather than a flavour of [outbound], because waste
  /// percentage and sell-through before expiry are computed by filtering on
  /// exactly this distinction.
  waste,

  /// A correction or a counted adjustment after a stock take.
  correction,
}

/// **MovementRow**
///
/// One entry in the append-only ledger: what happened, who did it, when, and by
/// how much.
///
/// The delta arrives already signed and already formatted, so this widget never
/// does arithmetic or decides a sign. It also means the sign is in the text rather
/// than carried only by the tint, which is what keeps the direction readable for a
/// user who cannot separate the colours.
///
/// ### Example
///
/// ```dart
/// MovementRow(
///   reason: 'Tüketildi', delta: '-1', unit: 'adet',
///   meta: 'Anılcan · bugün 09:14',
///   direction: MovementDirection.outbound,
/// )
/// ```
@immutable
class MovementRow extends StatelessWidget {
  static const Map<MovementDirection, IconData> _icons = {
    MovementDirection.inbound: Icons.add_circle_outline,
    MovementDirection.outbound: Icons.remove_circle_outline,
    MovementDirection.waste: Icons.delete_outline,
    MovementDirection.correction: Icons.tune_outlined,
  };

  /// The already-localised reason label, for example `'Tüketildi'`.
  final String reason;

  /// The already-signed, already-formatted delta, for example `'-1'` or `'+12'`.
  final String delta;

  /// The product's base unit.
  final String? unit;

  /// The already-formatted actor and timestamp line.
  final String? meta;

  /// Which way this movement pushed stock.
  final MovementDirection direction;

  /// Creates a [MovementRow].
  const MovementRow({
    super.key,
    required this.reason,
    required this.delta,
    required this.direction,
    this.unit,
    this.meta,
  });

  @override
  Widget build(BuildContext context) {
    final slots = movementRowRecipe()(variants: {'direction': direction.name});

    return WDiv(
      className: slots['root'],
      children: [
        WDiv(
          className: slots['leading'],
          children: [
            WIcon(_icons[direction]!, className: slots['icon']),
            WDiv(
              className: slots['body'],
              children: [
                WText(reason, className: slots['reason']),
                if (meta != null) WText(meta!, className: slots['meta']),
              ],
            ),
          ],
        ),
        WText(unit == null ? delta : '$delta $unit', className: slots['delta']),
      ],
    );
  }
}
