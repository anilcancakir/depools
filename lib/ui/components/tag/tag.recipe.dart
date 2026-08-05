import 'package:magic/magic.dart';

/// Variant recipe for [Tag]: a two-axis [WindRecipe] combining an `intent` axis
/// (neutral / primary / success / warning / danger) with a `size` axis
/// (sm / md). Semantic alias tokens only, so each pill carries its own dark pair
/// and re-skins with the theme. This is the boilerplate's example of a
/// multi-axis recipe.
const WindRecipe tagRecipe = WindRecipe(
  base: 'flex flex-row items-center rounded-full font-medium',
  variants: {
    'intent': {
      'neutral': 'bg-surface-container-high text-fg-muted',
      'primary': 'bg-primary-container text-fg',
      'success': 'bg-success text-on-primary',
      'warning': 'bg-warning text-on-primary',
      'danger': 'bg-destructive-container text-fg',
    },
    'size': {
      'sm': 'px-2 py-0.5 text-xs',
      'md': 'px-2.5 py-1 text-sm',
    },
  },
  defaultVariants: {'intent': 'neutral', 'size': 'sm'},
);
