// Hand-authored inventory status supplement.
//
// magic's `design:sync` only emits the 17 standard semantic roles; its alias
// mapping is hardcoded and will never include a product's own status vocabulary.
// This supplement carries Depools' seven status families as Wind className
// tokens, so a view can write `bg-expiring-soft` or `text-expired` directly
// instead of reaching for a raw hex.
//
// Every hex here is one of Apple's increased-contrast system colour values, or a
// tint derived from one. The default (non-increased-contrast) Apple values are
// NOT used: they do not clear WCAG AA on our surfaces, and the reasoning plus
// the measurements are recorded in the "Colour" section of DESIGN.md. Mirror any
// change here into the status table in DESIGN.md, then re-run
// `python3 bin/verify-design-contrast.py`, which parses this file.
//
// `expired` deliberately equals `destructive` so a product past its date and a
// dangerous action read identically, the same way uptizm makes `down` equal
// `destructive`.
//
// Merged into the alias map in `lib/main.dart`:
//   WindThemeData(aliases: {...designAliases, ...depoolsStatusAliases})
//
// The wind alias expander matches a whole unprefixed-or-prefixed token against a
// key, so each value is a `'<util>-[#light] dark:<util>-[#dark]'` pair.

/// Inventory status className aliases, four per status family.
///
/// For each status `s`:
/// - `bg-<s>` / `text-<s>`: the solid tone, for dots, icons and strong text.
/// - `bg-<s>-soft`: the badge background.
/// - `text-<s>-soft-foreground`: the badge label sitting on that background.
///
/// Colour never carries meaning alone here. Every badge built from these tokens
/// pairs the tone with an icon and a label, per WCAG 1.4.1, and that pairing is
/// also the only thing that keeps `low-stock` and `expiring` reliably apart:
/// Apple's increased-contrast yellow and orange both resolve to brown-red tones
/// in light mode and sit closer together than their default counterparts do.
const Map<String, String> depoolsStatusAliases = <String, String>{
  // in-stock: enough on hand (systemGreen, increased contrast)
  'bg-in-stock': 'bg-[#1F7434] dark:bg-[#30DB5B]',
  'text-in-stock': 'text-[#1F7434] dark:text-[#30DB5B]',
  'bg-in-stock-soft': 'bg-[#DCF5E3] dark:bg-[#0A2E16]',
  'text-in-stock-soft-foreground': 'text-[#1F7434] dark:text-[#30DB5B]',

  // low-stock: below par or reorder point (systemYellow, increased contrast)
  'bg-low-stock': 'bg-[#8A3E00] dark:bg-[#FFD426]',
  'text-low-stock': 'text-[#8A3E00] dark:text-[#FFD426]',
  'bg-low-stock-soft': 'bg-[#FFF0D6] dark:bg-[#3A2600]',
  'text-low-stock-soft-foreground': 'text-[#8A3E00] dark:text-[#FFD426]',

  // out-of-stock: none left (systemGray, increased contrast)
  'bg-out-of-stock': 'bg-[#5A5A5E] dark:bg-[#AEAEB2]',
  'text-out-of-stock': 'text-[#5A5A5E] dark:text-[#AEAEB2]',
  'bg-out-of-stock-soft': 'bg-[#EDEDEF] dark:bg-[#2A2A2C]',
  'text-out-of-stock-soft-foreground': 'text-[#5A5A5E] dark:text-[#AEAEB2]',

  // expiring: expires inside the window (systemOrange, increased contrast)
  'bg-expiring': 'bg-[#A82B00] dark:bg-[#FFB340]',
  'text-expiring': 'text-[#A82B00] dark:text-[#FFB340]',
  'bg-expiring-soft': 'bg-[#FFE6DC] dark:bg-[#3D1200]',
  'text-expiring-soft-foreground': 'text-[#A82B00] dark:text-[#FFB340]',

  // expired: past its date (systemRed, increased contrast; equals destructive)
  'bg-expired': 'bg-[#D70015] dark:bg-[#FF6961]',
  'text-expired': 'text-[#D70015] dark:text-[#FF6961]',
  'bg-expired-soft': 'bg-[#FFEAEC] dark:bg-[#40000A]',
  'text-expired-soft-foreground': 'text-[#D70015] dark:text-[#FF6961]',

  // wasted: discarded, spoiled, broken (systemBrown, increased contrast)
  'bg-wasted': 'bg-[#6B5439] dark:bg-[#B59469]',
  'text-wasted': 'text-[#6B5439] dark:text-[#B59469]',
  'bg-wasted-soft': 'bg-[#F2EBE0] dark:bg-[#2C2318]',
  'text-wasted-soft-foreground': 'text-[#6B5439] dark:text-[#B59469]',

  // ai: AI-driven surfaces (systemTeal, increased contrast).
  // Teal on purpose, not purple: the violet-to-pink gradient is the strongest
  // visual tell of an AI-generated interface, and this sits inside Apple's own
  // palette while staying clear of `primary` blue at badge size.
  'bg-ai': 'bg-[#00697C] dark:bg-[#5DE6FF]',
  'text-ai': 'text-[#00697C] dark:text-[#5DE6FF]',
  'bg-ai-soft': 'bg-[#D6F0F5] dark:bg-[#00323B]',
  'text-ai-soft-foreground': 'text-[#00697C] dark:text-[#5DE6FF]',
};
