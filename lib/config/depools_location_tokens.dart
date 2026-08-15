// Hand-authored location-hue supplement.
//
// A location carries a colour the user picked from a swatch (D119), stored as a
// hue NAME and resolved to a token pair here. `design:sync` emits a fixed table
// of 17 semantic aliases and silently drops anything else, so this file follows
// the same pattern as `depools_status_tokens.dart` and is merged into the alias
// map in `lib/main.dart`.
//
// The names match `Location::COLOURS` on the backend, which CHECKs the column
// against the same seven. Adding a hue is a change in both places plus the
// migration's constraint, AND a re-run of the separation check below.
//
// **Seven and not eight, because `orange` was measured and removed.** Apple's
// increased-contrast light values for yellow, orange and red all darken toward
// brown, and orange landed between the other two: CIEDE2000 of 9.2 against amber
// and 10.1 against red, against 13.3 for the same amber/orange pair in dark mode
// where they ARE distinguishable on screen. A swatch a user cannot tell from its
// neighbour is worse than one fewer swatch, since the whole point of the hue is
// telling two shelves apart. `bin/verify-design-contrast.py` measures every pair
// now, so the next hue proposed is checked rather than eyeballed.
//
// **The hues are Apple's increased-contrast system colours, so several of them
// hold the same hex as a status family.** That is agreement rather than reuse:
// both vocabularies are built from Apple's published values, and neither reads
// the other. The collision is deliberate and safe because of the rule DESIGN.md
// already enforces, read in the direction that is easy to miss: colour never
// carries meaning ALONE here, so `expired` always arrives as a soft-filled pill
// with an icon and the word, and a red shelf glyph therefore cannot be misread
// as a date warning. A location's colour identifies a place; it does not assert
// a state, and nothing in this app lets a bare tint claim one.
//
// Mirror any change into the location table in DESIGN.md, then re-run
// `python3 bin/verify-design-contrast.py`, which parses this file with the same
// reader it uses for the status families.

/// Location hue className aliases, two per hue, holding the same value.
///
/// For each hue `h`:
/// - `text-<h>-location`: the tinted glyph, in the tree and on the form's icon tiles.
/// - `bg-<h>-location`: the same tone as a fill, for the form's colour swatch.
///
/// **The swatch is the SOLID tone and not a soft tint of it**, so that what the user picks
/// is what the tree then draws. A soft pair existed here first and was removed: it made the
/// swatch a pale version of a glyph that renders at full strength two screens away, and
/// nothing else called it. The tick on a chosen swatch is `text-on-primary`, which flips
/// with the appearance exactly as these fills do (dark in light mode, bright in dark), so
/// one token covers all seven.
///
/// **The hue is suffixed rather than prefixed** (`text-blue-location`, not
/// `text-location-blue`) so the key cannot be a prefix of a Wind built-in. Wind
/// ships `text-blue-500` and friends, and a token whose first two segments match
/// a real colour family is the kind of near-miss that resolves to the wrong
/// thing rather than to nothing.
const Map<String, String> depoolsLocationAliases = <String, String>{
  // slate: the neutral, and the fallback for a location with no colour set
  // (systemGray, increased contrast)
  'text-slate-location': 'text-[#5A5A5E] dark:text-[#AEAEB2]',
  'bg-slate-location': 'bg-[#5A5A5E] dark:bg-[#AEAEB2]',

  // blue (systemBlue, increased contrast)
  'text-blue-location': 'text-[#0040DD] dark:text-[#409CFF]',
  'bg-blue-location': 'bg-[#0040DD] dark:bg-[#409CFF]',

  // teal (systemTeal, increased contrast)
  'text-teal-location': 'text-[#00697C] dark:text-[#5DE6FF]',
  'bg-teal-location': 'bg-[#00697C] dark:bg-[#5DE6FF]',

  // green (systemGreen, increased contrast)
  'text-green-location': 'text-[#1F7434] dark:text-[#30DB5B]',
  'bg-green-location': 'bg-[#1F7434] dark:bg-[#30DB5B]',

  // amber (systemYellow, increased contrast)
  'text-amber-location': 'text-[#8A3E00] dark:text-[#FFD426]',
  'bg-amber-location': 'bg-[#8A3E00] dark:bg-[#FFD426]',

  // red (systemRed, increased contrast)
  'text-red-location': 'text-[#D70015] dark:text-[#FF6961]',
  'bg-red-location': 'bg-[#D70015] dark:bg-[#FF6961]',

  // violet (systemPurple, increased contrast). Purple rather than indigo: the
  // indigo pair is what `accent` is built from, and a location tinted with the
  // app's own accent reads as selected rather than as violet.
  'text-violet-location': 'text-[#3D0099] dark:text-[#DA8FFF]',
  'bg-violet-location': 'bg-[#3D0099] dark:bg-[#DA8FFF]',
};
