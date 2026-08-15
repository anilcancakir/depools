import 'package:magic/magic.dart';

/// Builds the [WindRecipe] for the AppIcon component.
///
/// **One size and nothing else, because the caller owns both dimensions here.** Every other
/// component in this folder resolves a variant into a class string; this one resolves a class string
/// into a SIZE AND A COLOUR, which it then hands to an svg rather than to a font glyph. A variant
/// table would be a second vocabulary for the same thing, and callers already style it exactly as
/// they style a `WIcon`.
///
/// So the recipe carries the default a caller gets when it says nothing, and the component reads
/// whatever it is given through `WindParser`.
WindRecipe appIconRecipe() {
  return const WindRecipe(base: 'size-5');
}
