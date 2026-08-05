import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../expiry_badge/expiry_badge.dart';
import '../quantity/quantity.dart';
import 'lot_row.recipe.dart';

/// **LotRow**
///
/// One inbound batch of a product at a location: its expiry, what is left of it,
/// and when it arrived. The row a product detail screen repeats to show that three
/// cartons of milk carry three different dates.
///
/// A depleted lot is faded, not removed. It is the evidence behind the consumption
/// history, and dropping it would make the ledger look like it lost entries.
///
/// ### Example
///
/// ```dart
/// LotRow(
///   remaining: '1', unit: 'adet',
///   expiryLabel: '2 gün', daysUntilExpiry: 2,
///   receivedLabel: '3 Ağu alındı',
/// )
/// ```
@immutable
class LotRow extends StatelessWidget {
  /// The remaining quantity, already formatted for the locale.
  final String remaining;

  /// The product's base unit.
  final String? unit;

  /// The already-formatted expiry label, for example `'2 gün'`.
  final String? expiryLabel;

  /// Days until this lot expires. Negative means it already has, null means the
  /// lot carries no date.
  final int? daysUntilExpiry;

  /// The already-formatted arrival line, for example `'3 Ağu alındı'`.
  final String? receivedLabel;

  /// The supplier's batch code, when one is known.
  final String? lotCode;

  /// Whether this lot has reached zero.
  final bool isDepleted;

  /// Creates a [LotRow].
  const LotRow({
    super.key,
    required this.remaining,
    this.unit,
    this.expiryLabel,
    this.daysUntilExpiry,
    this.receivedLabel,
    this.lotCode,
    this.isDepleted = false,
  });

  @override
  Widget build(BuildContext context) {
    final slots = lotRowRecipe()(variants: {'state': isDepleted ? 'depleted' : 'active'});

    return WDiv(
      className: slots['root'],
      children: [
        WDiv(
          className: slots['leading'],
          children: [
            WDiv(
              className: slots['meta'],
              children: [
                if (expiryLabel != null)
                  ExpiryBadge(label: expiryLabel!, daysUntilExpiry: daysUntilExpiry),
                if (lotCode != null) WText(lotCode!, className: slots['code']),
              ],
            ),
            if (receivedLabel != null) WText(receivedLabel!, className: slots['received']),
          ],
        ),
        Quantity(value: remaining, unit: unit, isZero: isDepleted),
      ],
    );
  }
}
