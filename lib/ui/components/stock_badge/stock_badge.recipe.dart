import 'package:magic/magic.dart';

/// Builds the [WindRecipe] for the StockBadge component.
///
/// The stock-level counterpart to `expiryBadgeRecipe`, and it follows the same rules
/// for the same reasons: tones come from the status supplement in
/// `lib/config/depools_status_tokens.dart` so each already carries its light/dark
/// pair, and colour is never the only carrier (WCAG 1.4.1), so every variant pairs
/// its tone with an icon and a Turkish label.
///
/// **There is deliberately no `out` variant.** A depleted row already reads as
/// depleted: `Quantity` greys its own zero, and "0 adet" beside a grey name says it
/// better than a chip repeating the same fact would. A badge earns its place when the
/// number alone is not enough, and "3 adet" is exactly that case: three is only low
/// against a target the row does not show.
///
/// `low-stock` soft rather than solid, matching `expiring` rather than `expired`.
/// Running low is a plan-ahead signal, not a stop-work one, and reserving the solid
/// weight for the states that demand action today keeps the attention list readable
/// when several rows carry a chip at once.
WindRecipe stockBadgeRecipe() {
  return const WindRecipe(
    base: 'flex flex-row items-center gap-1 rounded-full px-2 py-0.5 text-xs font-medium',
    variants: {
      'level': {'low': 'bg-low-stock-soft text-low-stock-soft-foreground'},
    },
    defaultVariants: {'level': 'low'},
  );
}

/// The leading icon's className, sized to sit on the 12px label baseline.
WindRecipe stockBadgeIconRecipe() {
  return const WindRecipe(base: 'size-3');
}
