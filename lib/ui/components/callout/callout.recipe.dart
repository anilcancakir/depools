import 'package:magic/magic.dart';

/// Variant recipe for [Callout]: a single `intent` axis (neutral / info /
/// danger) rendered as a soft container tone. Semantic alias tokens only, so
/// each tone carries its own dark pair. The boilerplate's example of a
/// single-axis recipe on a composed (title + message) widget.
const WindRecipe calloutRecipe = WindRecipe(
  base: 'flex flex-col gap-1 rounded-lg px-4 py-3',
  variants: {
    'intent': {
      'neutral': 'bg-surface-container-high',
      'info': 'bg-primary-container',
      'danger': 'bg-destructive-container',
    },
  },
  defaultVariants: {'intent': 'neutral'},
);
