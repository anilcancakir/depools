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

/// What the figure means, which decides its colour.
enum QuantityTone {
  /// An ordinary stock figure.
  neutral,

  /// Secondary context, de-emphasised.
  muted,

  /// Stock coming in.
  inbound,

  /// Stock discarded.
  waste,
}

/// **Quantity**
///
/// A stock figure with its unit, set in Geist Mono so a column of values aligns
/// digit for digit.
///
/// It takes BOTH the raw [amount] and the [formatted] string, which looks redundant
/// and is not. Formatting has to stay with the caller, because Turkish inverts the
/// English separators (`1.240,00`, not `1,240.00`) and that is a locale decision.
/// But a widget that only receives the string cannot tell that it means zero, so an
/// earlier version took a separate `isZero` flag and a caller who forgot it rendered
/// `0` at full emphasis, silently losing the muted-zero treatment. Passing the raw
/// amount alongside makes the invariant impossible to break: the widget derives the
/// flag rather than trusting one.
///
/// A zero is muted, never hidden. "0 kg" is real information in an inventory, and
/// dropping it would make an out-of-stock item look like a missing one.
///
/// ### Example
///
/// ```dart
/// Quantity(amount: 1240, formatted: '1.240,00', unit: 'kg', size: QuantitySize.lg)
/// ```
@immutable
class Quantity extends StatelessWidget {
  /// The raw amount, used only to decide whether this reads as zero.
  final num amount;

  /// The already-formatted value for the active locale, for example `'1.240,00'`.
  final String formatted;

  /// The unit label, for example `'kg'` or `'adet'`.
  final String? unit;

  /// The size step.
  final QuantitySize size;

  /// What the figure means.
  final QuantityTone tone;

  /// Optional className appended after the value recipe's output.
  final String? className;

  /// Creates a [Quantity].
  const Quantity({
    super.key,
    required this.amount,
    required this.formatted,
    this.unit,
    this.size = QuantitySize.md,
    this.tone = QuantityTone.neutral,
    this.className,
  });

  /// The recipe tone key, derived rather than passed so it cannot drift.
  String get _toneKey {
    if (tone != QuantityTone.neutral) {
      return tone == QuantityTone.muted ? 'muted' : tone.name;
    }

    return amount == 0 ? 'zero' : 'default';
  }

  @override
  Widget build(BuildContext context) {
    final toneKey = _toneKey;

    return WDiv(
      className: quantityRecipe()(
        variants: {'size': size.name, 'tone': toneKey},
        className: className,
      ),
      children: [
        WText(formatted),
        if (unit != null)
          WText(
            unit!,
            className: quantityUnitRecipe()(
              variants: {'size': size.name, 'tone': toneKey},
            ),
          ),
      ],
    );
  }
}
