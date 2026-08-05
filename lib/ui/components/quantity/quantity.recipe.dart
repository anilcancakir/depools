import 'package:magic/magic.dart';

/// Builds the [WindRecipe] for the Quantity component.
///
/// `font-mono` resolves to Geist Mono through `fontFamilies` in `lib/main.dart`.
/// That is the whole point of this component: in a monospace every digit is the
/// same width by construction, so a column of quantities lines up without
/// depending on a proportional face shipping tabular numerals.
///
/// Colour comes from semantic aliases (`text-fg`, `text-fg-muted`), which already
/// expand to a light/dark pair, so no explicit `dark:` peer belongs here.
///
/// Emission order is `base ++ variant ++ compound ++ caller`.
WindRecipe quantityRecipe() {
  return const WindRecipe(
    base: 'flex flex-row items-baseline gap-1 font-mono',
    variants: {
      'size': {
        'sm': 'text-xs',
        'md': 'text-sm',
        'lg': 'text-lg',
      },
      'tone': {
        'default': 'text-fg',
        'muted': 'text-fg-muted',
        'zero': 'text-fg-muted',
      },
    },
    defaultVariants: {
      'size': 'md',
      'tone': 'default',
    },
  );
}

/// Builds the [WindRecipe] for the unit suffix.
///
/// A separate recipe rather than an interpolated string, because Core Law 3
/// forbids assembling a className from Dart expressions: a static map of whole
/// classNames keeps every value a parser-cache-friendly literal.
///
/// The unit sits one size step below its value and is muted, so the number leads
/// and the unit reads as an annotation rather than competing with it.
WindRecipe quantityUnitRecipe() {
  return const WindRecipe(
    base: 'font-mono text-fg-muted',
    variants: {
      'size': {
        'sm': 'text-xs',
        'md': 'text-xs',
        'lg': 'text-sm',
      },
    },
    defaultVariants: {
      'size': 'md',
    },
  );
}
