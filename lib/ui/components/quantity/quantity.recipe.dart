import 'package:magic/magic.dart';

/// The tone axis, shared by the value and unit recipes.
///
/// It has to be shared. An earlier version hardcoded `text-fg-muted` into the
/// unit's base with no tone axis, which made a tinted value plus unit
/// inexpressible: the caller's `className` appends to the VALUE recipe and can
/// never reach the unit's separate one. That gap is what pushed `MovementRow` into
/// hand-rolling its own mono run, so the app ended up with two renderings of the
/// same thing on one screen.
const Map<String, String> _valueTones = {
  'default': 'text-fg',
  'muted': 'text-fg-muted',
  'zero': 'text-fg-muted',
  'inbound': 'text-in-stock',
  'waste': 'text-wasted',
};

const Map<String, String> _unitTones = {
  'default': 'text-fg-muted',
  'muted': 'text-fg-muted',
  'zero': 'text-fg-muted',
  'inbound': 'text-in-stock',
  'waste': 'text-wasted',
};

/// Builds the [WindRecipe] for the Quantity value.
///
/// `font-mono` resolves to Geist Mono through `fontFamilies` in `lib/main.dart`.
/// That is the whole point: in a monospace every digit is the same width by
/// construction, so a column of quantities lines up without depending on a
/// proportional face shipping tabular numerals.
///
/// Colour comes from semantic aliases, which already expand to a light/dark pair,
/// so no explicit `dark:` peer belongs here.
WindRecipe quantityRecipe() {
  return const WindRecipe(
    base: 'flex flex-row items-baseline gap-1 font-mono',
    variants: {
      'size': {'sm': 'text-xs', 'md': 'text-sm', 'lg': 'text-lg'},
      'tone': _valueTones,
    },
    defaultVariants: {'size': 'md', 'tone': 'default'},
  );
}

/// Builds the [WindRecipe] for the unit suffix.
///
/// A recipe rather than an interpolated string, because Core Law 3 forbids
/// assembling a className from Dart expressions.
///
/// The unit sits one size step below its value. On the neutral tones it is also
/// muted so the number leads; on a tinted tone it takes the same colour, because a
/// muted grey unit beside a green number reads as two unrelated pieces.
WindRecipe quantityUnitRecipe() {
  return const WindRecipe(
    base: 'font-mono',
    variants: {
      'size': {'sm': 'text-xs', 'md': 'text-xs', 'lg': 'text-sm'},
      'tone': _unitTones,
    },
    defaultVariants: {'size': 'md', 'tone': 'default'},
  );
}
