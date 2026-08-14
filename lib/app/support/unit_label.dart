import 'plural.dart';

/// The words for a stored unit code.
///
/// **A `base_unit` is a CODE, not copy, and printing it raw is what put `1 adet` on an English
/// screen.** The codes are UN/ECE Recommendation 20, which is what e-Fatura already puts on the wire
/// (`C62` a piece, `KGM` a kilogram, `LTR` a litre), so they are unreadable by design: nobody was ever
/// meant to see them.
///
/// ### Why this is a hand-written catalogue rather than a formatter
///
/// Neither stack gives a localised unit word for free. CLDR has them, and Dart's `intl` exposes none
/// of it: checked against 0.20.2, there is no `MeasureFormat`, no unit patterns, nothing. PHP's
/// `ext-intl` is the same on the server side. So a unit's label is one translation per code, which is
/// exactly why the vocabulary is a small seeded set rather than the standard's ~2,100 entries.
///
/// ### An unknown code is shown as it stands
///
/// A tenant may add their own unit, and their code IS their word for it (`koli`, `case`). There is no
/// catalogue entry for that and there should not be: it is already in their language. So a miss falls
/// back to the code, which is right for a tenant unit and, for a shared code nobody translated, is at
/// least the honest string rather than a blank.
String unitLabel(String code, [int count = 1]) {
  final String trimmed = code.trim();

  if (trimmed.isEmpty) {
    return trimmed;
  }

  // Lower-cased because the catalogue keys are, while Rec 20 codes are upper-case (`KGM`). Dart's
  // `toLowerCase` is locale-independent, so the Turkish dotless-i rule cannot bite here.
  final String key = 'units.${trimmed.toLowerCase()}';
  final String label = plural(key, count);

  // `Lang.get` answers with the key itself when nothing is registered under it, which is what makes
  // this a miss rather than a lookup that silently returned something.
  return label == key ? trimmed : label;
}
