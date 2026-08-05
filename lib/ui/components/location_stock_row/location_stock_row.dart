import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../expiry_badge/expiry_badge.dart';
import '../quantity/quantity.dart';
import 'location_stock_row.recipe.dart';

/// **LocationStockRow**
///
/// How much of one product sits at one location, with the earliest expiry among
/// that location's lots.
///
/// The path arrives already joined ("Kiler › Raf 2") rather than as a list, because
/// how deep a hierarchy to show and which separator to use are presentation
/// decisions the caller makes once, and passing a list would push that decision
/// into every row.
///
/// Only the earliest expiry is surfaced. A location holding four lots does not need
/// four badges here; that detail belongs to the lot list, and repeating it would
/// bury the number the user is scanning for.
///
/// ### Example
///
/// ```dart
/// LocationStockRow(
///   path: 'Kiler › Raf 2', quantity: '2', unit: 'adet',
///   lotsLabel: '2 parti', expiryLabel: '2 gün', daysUntilExpiry: 2,
/// )
/// ```
@immutable
class LocationStockRow extends StatelessWidget {
  /// The already-joined location path, for example `'Kiler › Raf 2'`.
  final String path;

  /// The quantity at this location, already formatted for the locale.
  final String quantity;

  /// The product's base unit.
  final String? unit;

  /// An already-formatted lot count, for example `'2 parti'`.
  final String? lotsLabel;

  /// The already-formatted earliest expiry among this location's lots.
  final String? expiryLabel;

  /// Days until that earliest expiry.
  final int? daysUntilExpiry;

  /// Whether this location currently holds none of the product.
  final bool isEmpty;

  /// Creates a [LocationStockRow].
  const LocationStockRow({
    super.key,
    required this.path,
    required this.quantity,
    this.unit,
    this.lotsLabel,
    this.expiryLabel,
    this.daysUntilExpiry,
    this.isEmpty = false,
  });

  @override
  Widget build(BuildContext context) {
    final slots = locationStockRowRecipe()(
      variants: {'state': isEmpty ? 'empty' : 'stocked'},
    );

    return WDiv(
      className: slots['root'],
      children: [
        WDiv(
          className: slots['leading'],
          children: [
            WText(path, className: slots['path']),
            if (lotsLabel != null) WText(lotsLabel!, className: slots['meta']),
          ],
        ),
        WDiv(
          className: slots['trailing'],
          children: [
            Quantity(value: quantity, unit: unit, isZero: isEmpty),
            if (expiryLabel != null)
              ExpiryBadge(label: expiryLabel!, daysUntilExpiry: daysUntilExpiry),
          ],
        ),
      ],
    );
  }
}
