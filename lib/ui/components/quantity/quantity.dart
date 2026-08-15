import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../../app/support/unit_label.dart';
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
/// ### The open remainder
///
/// [remainderFormatted] renders a second figure after a `+`, for the case where some
/// units are whole and one is open: "2 adet + 500 ml". Per D26 a partial quantity is
/// never one decimal, because "2,5 adet" and especially "0,67 paket" correspond to
/// nothing a user can see in the cupboard.
///
/// **Which figure is primary is the caller's decision, not this widget's.** When
/// nothing is whole, the caller passes the open remainder AS [formatted] and leaves
/// the remainder null, so a pack with two sachets left reads "2 poşet" rather than
/// "0 paket + 2 poşet". That choice needs the product's content declaration and the
/// locale's pluralisation, both of which already live with the caller.
///
/// ### Example
///
/// ```dart
/// Quantity(amount: 1240, formatted: '1.240,00', unit: 'kg', size: QuantitySize.lg)
/// Quantity(amount: 2.5, formatted: '2', unit: 'adet', remainderFormatted: '500', remainderUnit: 'ml')
/// ```
@immutable
class Quantity extends StatelessWidget {
  /// The raw amount, used only to decide whether this reads as zero.
  final num amount;

  /// The already-formatted value for the active locale, for example `'1.240,00'`.
  final String formatted;

  /// The unit CODE, for example `'C62'` or `'KGM'`.
  ///
  /// **Resolved to a word here rather than by the caller**, which is the whole reason this parameter
  /// changed meaning. Since the vocabulary became UN/ECE Rec 20 codes, every screen that printed this
  /// straight showed `1240 C62` at the user; the scan screen resolved it and nothing else did.
  /// Pluralisation needs the count, and this widget is the one place that already holds both the
  /// number and the unit, so it is the only place where the two cannot drift apart.
  ///
  /// A code with no entry in the catalogue falls through as it stands, which is right for a tenant's
  /// own unit: their code IS their word for it (`koli`, `case`).
  final String? unit;

  /// An already-formatted second figure for the open unit's remainder.
  ///
  /// Rendered after a `+`. Null when nothing is open, or when the remainder is
  /// itself the primary figure (see the class docs).
  final String? remainderFormatted;

  /// The remainder's unit, the product's content unit rather than its base unit.
  final String? remainderUnit;

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
    this.remainderFormatted,
    this.remainderUnit,
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
    final unitClassName = quantityUnitRecipe()(variants: {'size': size.name, 'tone': toneKey});

    return WDiv(
      className: quantityRecipe()(
        variants: {'size': size.name, 'tone': toneKey},
        className: className,
      ),
      children: [
        WText(formatted),
        // [amount] is the raw total, which is the count this unit belongs to in every shape rendered
        // here: a whole count, a fractional one, and the case where the caller passes the open
        // remainder as [formatted] and the total IS that remainder. `unitLabel` takes a `num` and
        // owns the singular-versus-plural rule, so there is nothing to decide at this call site.
        if (unit != null) WText(unitLabel(unit!, amount), className: unitClassName),
        // The `+` takes the unit's muted tone rather than the value's. It is a
        // separator, not a figure, and at the value's weight it competed with both
        // numbers it sits between.
        if (remainderFormatted != null) ...[
          WText('+', className: unitClassName),
          WText(remainderFormatted!),
          // Against the remainder's OWN figure rather than [amount], which is the total and would
          // pluralise the second unit by the first one's count. The raw number never reaches this
          // widget, so the formatted string is what the count is read from.
          if (remainderUnit != null)
            WText(unitLabelFor(remainderUnit!, remainderFormatted ?? ''), className: unitClassName),
        ],
      ],
    );
  }
}
