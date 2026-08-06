import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../expiry_badge/expiry_badge.dart';
import '../quantity/quantity.dart';
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

  /// The already-formatted earliest expiry across every lot.
  final String? expiryLabel;

  /// Days until that earliest expiry.
  final int? daysUntilExpiry;

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
    this.expiryLabel,
    this.daysUntilExpiry,
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
              Quantity(amount: amount, formatted: formatted, unit: unit),
              ?ExpiryBadge.maybe(label: expiryLabel, daysUntilExpiry: daysUntilExpiry),
            ],
          ),
        ],
      ),
    );
  }
}
