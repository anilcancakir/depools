import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../expiry_badge/expiry_badge.dart';
import '../quantity/quantity.dart';
import '../stock_badge/stock_badge.dart';
import 'product_row.recipe.dart';

/// **ProductRow**
///
/// One product in a list: what it is, roughly where it lives, how much there is in
/// total, and whether anything about it needs attention.
///
/// Distinct from `LocationStockRow` on purpose. That row answers "how much of this
/// product is at this location" and repeats per location inside a product's detail;
/// this one answers "what is this and how much is there altogether" and repeats per
/// product in a list. Merging them would mean one component with two meanings for its
/// quantity, which is how a list starts showing per-location numbers as if they were
/// totals.
///
/// [locationSummary] is already-joined text like "Buzdolabı, Kiler" or "2 konumda",
/// because how many locations to name before collapsing to a count is a presentation
/// decision, and pushing a list into every row would make the caller build the same
/// string anyway.
///
/// ### Example
///
/// ```dart
/// ProductRow(
///   name: 'Pınar Süt Tam Yağlı 1 lt',
///   meta: 'Pınar · Buzdolabı, Kiler',
///   amount: 5, formatted: '5', unit: 'adet',
///   expiryLabel: 'Süresi geçti', daysUntilExpiry: -1,
/// )
/// ```
@immutable
class ProductRow extends StatelessWidget {
  static const IconData _thumbIcon = Icons.photo_outlined;

  /// The product name, already localised. Truncates rather than wrapping.
  final String name;

  /// The already-joined brand and location line.
  final String? meta;

  /// The raw total across every location, used to derive the zero treatment.
  final num amount;

  /// The already-formatted total for the active locale.
  final String formatted;

  /// The product's base unit.
  final String? unit;

  /// An already-formatted remainder for an open unit, rendered after a `+`.
  final String? remainderFormatted;

  /// The remainder's unit.
  final String? remainderUnit;

  /// The already-formatted earliest expiry across every lot.
  final String? expiryLabel;

  /// Days until that earliest expiry.
  final int? daysUntilExpiry;

  /// The user-set target level, used to decide whether to show a low-stock badge.
  ///
  /// Without this the row cannot say WHY a product with stock on hand needs
  /// attention. "3 adet" is not low on its own; it is low against a target of ten,
  /// and a warning that does not name its own cause gets ignored or distrusted.
  final num? parLevel;

  /// Called when the row is tapped, which opens the product.
  final VoidCallback? onTap;

  /// Creates a [ProductRow].
  const ProductRow({
    super.key,
    required this.name,
    required this.amount,
    required this.formatted,
    this.meta,
    this.unit,
    this.remainderFormatted,
    this.remainderUnit,
    this.expiryLabel,
    this.daysUntilExpiry,
    this.parLevel,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final slots = productRowRecipe()(variants: {'state': amount == 0 ? 'depleted' : 'stocked'});

    return WAnchor(
      onTap: onTap,
      child: WDiv(
        className: slots['root'],
        children: [
          WDiv(
            className: slots['thumb'],
            child: const WIcon(_thumbIcon, className: 'size-5 text-fg-disabled'),
          ),
          WDiv(
            className: slots['body'],
            children: [
              WText(name, className: slots['name']),
              if (meta != null) WText(meta!, className: slots['meta']),
            ],
          ),
          WDiv(
            className: slots['trailing'],
            children: [
              Quantity(
                amount: amount,
                formatted: formatted,
                unit: unit,
                remainderFormatted: remainderFormatted,
                remainderUnit: remainderUnit,
              ),
              // ONE badge, the most urgent. A product can be both expired and below
              // par, and rendering both stacked them into a three-line row: the
              // attention list lost its uniform rhythm and the date, which is the
              // signal with a deadline, stopped leading. Whichever is worse is what
              // the user acts on first, and acting on it changes the other anyway
              // (throwing out the expired carton makes the shortfall bigger).
              //
              // The full picture belongs on the detail screen, which has the room to
              // show the target level and every lot date at once.
              ?_buildBadge(),
            ],
          ),
        ],
      ),
    );
  }

  /// The single most urgent status, or null when nothing needs saying.
  ///
  /// Order: expired, then expiring, then below par. Expiry outranks stock level
  /// because it has a deadline that no amount of reordering fixes.
  Widget? _buildBadge() {
    final Widget? expiry = ExpiryBadge.maybe(label: expiryLabel, daysUntilExpiry: daysUntilExpiry);
    if (expiry != null) return expiry;
    return StockBadge.maybe(amount: amount, parLevel: parLevel);
  }
}
