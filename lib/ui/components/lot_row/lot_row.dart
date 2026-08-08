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
/// ### The open lot
///
/// [isOpen] marks the one lot that has been started. It gets an AÇIK tag and, per
/// D27, its own date: an opened carton with a week left on the box has three days
/// left in practice, so showing the printed date here would be the screen telling
/// the user the opposite of the truth.
///
/// This is why the lot list, not the total, is where partial consumption is legible.
/// The row above says "2 adet + 500 ml"; this list says which 500 ml, opened when,
/// and by which date it has to go.
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
  /// The raw remaining amount, used to derive the zero treatment.
  /// The product this lot belongs to, when the list spans more than one.
  ///
  /// Null on a product's own page, where every row shares the product and the expiry is
  /// what separates them. Present in the expiring list, where the opposite is true. Same
  /// rule `MovementRow` follows: the primary line carries whatever distinguishes this row
  /// from its neighbours.
  final String? productName;

  final num remainingAmount;

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

  /// Whether this lot has been opened and is on its after-opening clock.
  final bool isOpen;

  /// The already-formatted opening line, for example `'5 Ağu açıldı'`.
  ///
  /// Replaces [receivedLabel] when set, rather than joining it. Once something is
  /// open, when it arrived stops being the useful fact.
  final String? openedLabel;

  /// Whether this lot has reached zero.
  ///
  /// Derived by the caller from the ledger rather than from [remainingAmount],
  /// because a lot closed at zero and a lot that momentarily reads zero mid-count
  /// are different states.
  final bool isDepleted;

  /// Creates a [LotRow].
  const LotRow({
    this.productName,
    super.key,
    required this.remainingAmount,
    required this.remaining,
    this.unit,
    this.expiryLabel,
    this.daysUntilExpiry,
    this.receivedLabel,
    this.lotCode,
    this.isDepleted = false,
    this.isOpen = false,
    this.openedLabel,
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
            if (productName != null) WText(productName!, className: slots['product']),
            WDiv(
              className: slots['meta'],
              children: [
                if (isOpen) WText(Lang.get('components.lot_row.open'), className: slots['openTag']),
                ?ExpiryBadge.maybe(label: expiryLabel, daysUntilExpiry: daysUntilExpiry),
                if (lotCode != null) WText(lotCode!, className: slots['code']),
              ],
            ),
            // The opening date wins over the arrival date. Both would be two muted
            // lines saying almost the same thing, and only one of them bounds when
            // this has to be used.
            if (isOpen && openedLabel != null)
              WText(openedLabel!, className: slots['received'])
            else if (receivedLabel != null)
              WText(receivedLabel!, className: slots['received']),
          ],
        ),
        Quantity(amount: isDepleted ? 0 : remainingAmount, formatted: remaining, unit: unit),
      ],
    );
  }
}
