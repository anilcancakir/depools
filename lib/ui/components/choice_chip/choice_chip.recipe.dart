import 'package:magic/magic.dart';

/// Builds the [WindRecipe] for the ChoiceChip component.
///
/// **Not FilterChip, and the reason is in FilterChip's own body**: it bakes
/// `'$label filtresini uygula'` into its `semanticLabel`. An assistant chip that answers
/// "nereye koyalım" is not applying a filter, so reusing it would announce something false
/// to a screen reader, which is the one kind of reuse that is worse than a second
/// component. It is also simpler: a choice is taken once, so there is no applied state and
/// no remove affordance.
///
/// The touch target is carried by `min-h-11` on a plain `WDiv`, which is correct here and
/// is NOT the measured `MSButton` trap: min-height only fails to re-centre on that
/// component. On a WDiv it measures true.
WindRecipe choiceChipRecipe() {
  return const WindRecipe(
    base:
        'flex flex-row items-center gap-1.5 px-4 min-h-11 rounded-full axis-min '
        'bg-surface-container-high',
    variants: {
      'emphasis': {
        // The suggested answer. Every grouped card pre-fills a real, likely default, and
        // this is what marks it.
        'suggested': 'bg-primary-container border border-color-border',
        'plain': '',
      },
    },
    defaultVariants: {'emphasis': 'plain'},
  );
}
