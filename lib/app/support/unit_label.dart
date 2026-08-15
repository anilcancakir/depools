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
/// [count] is a `num` rather than an `int` because a quantity here is one: half a litre and 2.5 kg are
/// ordinary values, and a caller forced to round first would have to decide whether 1.4 is one.
/// Exactly one is singular and everything else is plural, which is the rule for both languages this
/// ships in and is decided here rather than at each call site.
String unitLabel(String code, [num count = 1]) {
  final String trimmed = code.trim();

  if (trimmed.isEmpty) {
    return trimmed;
  }

  // Lower-cased because the catalogue keys are, while Rec 20 codes are upper-case (`KGM`). Dart's
  // `toLowerCase` is locale-independent, so the Turkish dotless-i rule cannot bite here.
  final String key = 'units.${trimmed.toLowerCase()}';
  final String label = plural(key, count == 1 ? 1 : 2);

  // `Lang.get` answers with the key itself when nothing is registered under it, which is what makes
  // this a miss rather than a lookup that silently returned something.
  return label == key ? trimmed : label;
}

/// [unitLabel] for a caller that holds the already-formatted number rather than the raw one.
///
/// **Most display sites only have the string.** A row is handed `'1.240,00'` because formatting is a
/// locale decision that belongs with whoever built the figure, and the unit beside it still has to
/// agree in number. Rather than each of them writing its own parse, the rule lives here once.
///
/// Only exactly one is singular, so a failed parse is plural, which is the right answer for both ways
/// it fails: a grouped Turkish figure like `1.240,00` is never one, and a half-typed field is not one
/// either. The comma is swapped for a dot first, because `2,5` is how the decimal is written in the
/// locale this was drawn for.
String unitLabelFor(String code, String formatted) {
  return unitLabel(code, pluralCountOf(formatted));
}

/// The number a formatted figure should make its unit agree with.
///
/// Separate from [unitLabelFor] so it can be TESTED. The catalogue does not resolve in the test
/// harness (see `unit_label_test.dart` for the measurement), so every code falls back to itself there
/// and an assertion on the returned word cannot tell 1 from 2. The count is the part with a rule in
/// it, so the count is what is exposed and pinned.
num pluralCountOf(String formatted) {
  return num.tryParse(formatted.replaceAll(',', '.')) ?? 2;
}
