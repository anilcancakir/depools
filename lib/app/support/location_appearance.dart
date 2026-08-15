/// How a location's stored HUE becomes a className the app can draw with.
///
/// **The icon half of this file is gone, and where it went is the point.** It held sixteen names of
/// our own invention mapped to `const IconData`, because `--tree-shake-icons` drops a glyph no
/// constant references and a searchable set of all 4,185 would have cost +1.81 MB. The catalogue is
/// a table now, served as svg and drawn by `AppIcon`, so there is nothing here for an icon to
/// resolve to: a name goes to the server and an svg comes back.
///
/// **The colour is still a name** because `bin/design-tokens` fails the build on a raw hex, and
/// because a free colour has no contrast guarantee on either surface. Each hue resolves to a
/// className token from `depoolsLocationAliases` in `lib/config/depools_location_tokens.dart`, and
/// each carries its own `dark:` pair. The names match `Location::COLOURS`, which CHECKs the column
/// against the same seven, and that constraint stays because seven hues genuinely is a closed set.
library;

/// The hue a location falls back to when it has none.
///
/// `locations.colour` is nullable and a location created by a scan has never been given one, so the
/// neutral is what the tree draws rather than nothing at all.
const String locationFallbackColour = 'slate';

/// The seven hues a location may carry, in the order a swatch should offer them.
///
/// Neutral first, then around the wheel, so the picker reads as a spectrum with the opt-out at the
/// start rather than as an arbitrary list.
const List<String> locationColours = <String>[
  'slate',
  'blue',
  'teal',
  'green',
  'amber',
  'red',
  'violet',
];

/// The className for a location's tinted glyph, as it appears in the tree and the picker.
String locationGlyphClassName(String? colour) => 'text-${_hue(colour)}-location';

/// The className for a location's hue as a FILL, which is what the form's swatch draws.
///
/// The same tone as the glyph rather than a soft tint of it, so the swatch the user taps
/// predicts the row they will get.
String locationSwatchClassName(String? colour) => 'bg-${_hue(colour)}-location';

/// A stored colour name, or the fallback when it is absent or not one we know.
///
/// Interpolating an unknown hue would produce a token the alias map does not hold, and wind drops an
/// unknown token SILENTLY: the glyph would render at full foreground brightness and look like a
/// deliberate choice rather than a miss. Narrowing to the known set here is what stops that.
String _hue(String? colour) =>
    locationColours.contains(colour) ? colour! : locationFallbackColour;
