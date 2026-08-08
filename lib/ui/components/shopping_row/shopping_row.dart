import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../quantity/quantity.dart';
import 'shopping_row.recipe.dart';

/// Why a line is on the shopping list.
///
/// **The five values are three certainty tiers plus two facts.** `forecasting.md` splits a
/// product by how much history it has (0-1, 2-9, 10+ movements) and forbids a forecast
/// below the top tier. [runningOut], [roughlyDue] and [belowTarget] are those three tiers,
/// and which one a product lands in decides the SHAPE of the claim its line can make.
/// [expiring] and [manual] carry no forecast at all.
enum ShoppingReason {
  /// 10+ movements: a real days-of-cover figure from SBA.
  runningOut,

  /// 2-9 movements: an interval average, which is not a forecast and never renders as a
  /// number.
  roughlyDue,

  /// 0-1 movements: below a par level the user set. A threshold fact, no time claim.
  belowTarget,

  /// A lot expires soon, so it needs replacing whatever the consumption rate says.
  expiring,

  /// The user put it there.
  manual,
}

/// **ShoppingRow**
///
/// One line of the shopping list: tick it, read how much, and see why it is there.
///
/// **The reason is not decoration.** `forecasting.md`'s third acceptance criterion is that
/// every line states why it is there, and its own argument is that a checkable suggestion
/// is one the user can trust. So the reason renders on every line including the manual
/// ones, where it says the user added it.
///
/// **The precision of the sentence IS the uncertainty display** (D46). The doc leaves this
/// open, saying no good precedent was found for showing a probabilistic inventory forecast
/// to a non-technical user. The answer taken here is to let the language degrade with the
/// data instead of inventing a visual vocabulary for doubt:
///
/// - 10+ movements: `2 günlük kaldı`. A number, because there is one.
/// - 2-9 movements: `Yaklaşık bir hafta`. A bucket. Never a number, at any precision.
/// - 0-1 movements: `Hedefin altında · 1 / 4 adet`. No time claim at all, just the ratio.
///
/// A user cannot misread a bucket as a measurement, nothing new has to be learned, and it
/// degrades in the direction that is safe. It is what weather forecasts do, for the same
/// reason: "rain this afternoon" when the model cannot say three o'clock.
///
/// **Ticking is not a stock movement** (D47). It means the item is in the trolley. Stock
/// arrives when the receipt is scanned or a stock-in is recorded, and a tick that wrote
/// stock would give every user phantom inventory for everything they put back on the shelf.
@immutable
class ShoppingRow extends StatelessWidget {
  static const IconData _checkIcon = Icons.check;
  static const IconData _runningOutIcon = Icons.hourglass_bottom_outlined;
  static const IconData _roughlyDueIcon = Icons.schedule_outlined;
  static const IconData _belowTargetIcon = Icons.trending_down_outlined;
  static const IconData _expiringIcon = Icons.event_busy_outlined;
  static const IconData _manualIcon = Icons.edit_outlined;

  /// The product name.
  final String name;

  /// The raw quantity to buy, for the zero treatment.
  final num amount;

  /// The already-formatted quantity.
  final String formatted;

  /// The unit.
  final String unit;

  /// Why this line is here.
  final ShoppingReason reason;

  /// The already-localised evidence behind the reason, for example `'2 günlük kaldı'` or
  /// `'1 / 4 adet'`. Composed by the caller because only it knows the tier's arithmetic.
  final String reasonDetail;

  /// Whether the item is in the trolley.
  final bool isChecked;

  /// Called when the tick is toggled.
  final VoidCallback? onToggle;

  /// Creates a [ShoppingRow].
  const ShoppingRow({
    super.key,
    required this.name,
    required this.amount,
    required this.formatted,
    required this.reasonDetail,
    this.unit = 'adet',
    this.reason = ShoppingReason.manual,
    this.isChecked = false,
    this.onToggle,
  });

  /// The reason's glyph. Present on every line, so the reason text never shifts.
  IconData get _reasonIcon => switch (reason) {
    ShoppingReason.runningOut => _runningOutIcon,
    ShoppingReason.roughlyDue => _roughlyDueIcon,
    ShoppingReason.belowTarget => _belowTargetIcon,
    ShoppingReason.expiring => _expiringIcon,
    ShoppingReason.manual => _manualIcon,
  };

  /// The glyph's tone.
  ///
  /// Only the two reasons with a deadline take a status tone, and they take the family that
  /// names their own deadline: `expiring` for a date, `low-stock` for a level. The other
  /// three recede, because a list where every line is coloured is a list with no priority
  /// in it.
  String get _reasonTone => switch (reason) {
    ShoppingReason.expiring => 'size-3.5 text-expiring',
    ShoppingReason.runningOut => 'size-3.5 text-low-stock',
    _ => 'size-3.5 text-fg-disabled',
  };

  @override
  Widget build(BuildContext context) {
    final slots = shoppingRowRecipe()(variants: {'state': isChecked ? 'checked' : 'open'});

    return WAnchor(
      onTap: onToggle,
      semanticLabel: Lang.get(
        isChecked ? 'components.shopping_row.label_checked' : 'components.shopping_row.label',
        {'name': name, 'amount': formatted, 'unit': unit, 'reason': reasonDetail},
      ),
      child: WDiv(
        className: slots['root'],
        children: [
          // The tick sits in the gutter because it is what a person touches while holding a
          // basket. The reason's glyph goes with the reason text, one line down, where it
          // annotates rather than competes.
          // The box is always drawn, so the reserved-gutter rule is satisfied by the box
          // rather than by its contents: nothing shifts when the tick appears. A greyed
          // tick in every empty box would make the list look half-walked at a glance,
          // which is the one thing this column exists to answer.
          WDiv(
            className: slots['box'],
            child: isChecked ? WIcon(_checkIcon, className: slots['boxIcon']) : null,
          ),
          WDiv(
            className: slots['body'],
            children: [
              WText(name, className: slots['name']),
              WDiv(
                className: slots['reason'],
                children: [
                  WIcon(_reasonIcon, className: _reasonTone),
                  // A ticked row KEEPS its reason. An earlier pass replaced it with
                  // "Sepette", which the section header above it already says; the reason
                  // is what the user checks the quantity against while holding the thing,
                  // so it is exactly the line that must survive the tick.
                  WText(reasonDetail, className: slots['reasonText']),
                ],
              ),
            ],
          ),
          // Full weight in both states: a ticked line is the one being held while the
          // number on the shelf label is checked against it.
          WDiv(
            className: slots['trailing'],
            child: Quantity(amount: amount, formatted: formatted, unit: unit),
          ),
        ],
      ),
    );
  }
}
