import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import 'stock_badge.recipe.dart';

/// **StockBadge**
///
/// Says why a row with stock on hand still needs attention: it has fallen to or
/// below the target level the user set for it.
///
/// It exists because generalising the app past food exposed a gap. A row reading
/// "USB-C Kablo, 3 adet" sat in the attention section with nothing explaining why,
/// while its neighbours carried "Süresi geçti" and "2 gün". That is the same defect
/// class as an invisible active filter: a warning that does not say what it is
/// warning about, which the reader either ignores or distrusts.
///
/// Three is not low on its own. It is low against a target of ten, and the row does
/// not show the target, so the badge has to carry the judgement.
///
/// ### Use [maybe] rather than a conditional at the call site
///
/// ```dart
/// WDiv(children: [
///   Quantity(amount: amount, formatted: formatted, unit: unit),
///   ?StockBadge.maybe(amount: amount, parLevel: parLevel),
/// ])
/// ```
///
/// [maybe] returns null when the product is not below par, including when no target
/// is set. Returning a widget that renders nothing would leave a phantom gap in the
/// parent's `gap-1`, which is a bug this project has already shipped once.
@immutable
class StockBadge extends StatelessWidget {
  static const IconData _lowIcon = Icons.trending_down_outlined;

  /// The already-localised label. Defaults to the below-par wording.
  /// Null takes the component's own wording from the catalogue.
  ///
  /// **Nullable rather than defaulted, because a `const` constructor cannot look a key up.** A
  /// default parameter value has to be a compile-time constant, and a catalogue lookup is not one.
  /// Resolving in `build` also means the label follows a locale change rather than freezing at the
  /// moment the widget was constructed.
  final String? label;

  /// Creates a [StockBadge].
  const StockBadge({super.key, this.label});

  /// Returns a badge only when [amount] is at or below [parLevel].
  ///
  /// Null [parLevel] returns null: an unset target cannot be breached, and treating
  /// it as zero would badge every product in the catalogue. A zero [amount] also
  /// returns null, because a depleted row already reads as depleted and does not need
  /// a chip saying so a second time.
  static StockBadge? maybe({required num amount, num? parLevel, String? label}) {
    if (parLevel == null || amount <= 0 || amount > parLevel) return null;
    return StockBadge(label: label);
  }

  @override
  Widget build(BuildContext context) {
    return WDiv(
      className: stockBadgeRecipe()(variants: {'level': 'low'}),
      children: [
        WIcon(_lowIcon, className: stockBadgeIconRecipe()()),
        WText(label ?? Lang.get('components.stock_badge.low')),
      ],
    );
  }
}
