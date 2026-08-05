import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import 'quantity.recipe.dart';

/// The quantity size axis.
enum QuantitySize {
  /// Compact, for dense rows.
  sm,

  /// Default.
  md,

  /// Prominent, for a product's headline stock figure.
  lg,
}

/// **Quantity**
///
/// A stock figure with its unit, set in Geist Mono so a column of quantities
/// aligns digit for digit.
///
/// Formatting is the caller's job: this widget renders the string it is given and
/// never parses or rounds. Rounding a quantity is a domain decision, and Turkish
/// number formatting inverts the English separators (`1.240,00`, not `1,240.00`),
/// so a value must arrive already formatted for the active locale rather than
/// interpolated from a raw double.
///
/// A zero quantity is muted, never hidden. "0 kg" is meaningful in an inventory,
/// and dropping it would make an out-of-stock item look like a missing one.
///
/// ### Example
///
/// ```dart
/// Quantity(value: '1.240,00', unit: 'kg', size: QuantitySize.lg)
/// ```
@immutable
class Quantity extends StatelessWidget {
  /// The already-formatted numeric value, for example `'1.240,00'`.
  final String value;

  /// The unit label, for example `'kg'` or `'adet'`.
  final String? unit;

  /// The size step.
  final QuantitySize size;

  /// Whether this quantity reads as zero, which mutes it.
  final bool isZero;

  /// Whether to mute the value regardless of amount, for secondary contexts.
  final bool muted;

  /// Optional className appended after the recipe output.
  final String? className;

  /// Creates a [Quantity].
  const Quantity({
    super.key,
    required this.value,
    this.unit,
    this.size = QuantitySize.md,
    this.isZero = false,
    this.muted = false,
    this.className,
  });

  @override
  Widget build(BuildContext context) {
    final tone = isZero || muted ? (isZero ? 'zero' : 'muted') : 'default';

    return WDiv(
      className: quantityRecipe()(
        variants: {'size': size.name, 'tone': tone},
        className: className,
      ),
      children: [
        WText(value),
        if (unit != null)
          WText(
            unit!,
            className: quantityUnitRecipe()(variants: {'size': size.name}),
          ),
      ],
    );
  }
}
