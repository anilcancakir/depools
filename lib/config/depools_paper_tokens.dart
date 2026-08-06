// Hand-authored print-surface supplement.
//
// Every other colour in this app flips with the appearance, because every other
// surface is one the user reads on a screen. These do not, and that is the whole
// point of them: a label preview is a picture OF PAPER. The sheet in the tray is
// white at two in the morning too, and a preview that rendered it dark would be
// showing something the printer cannot produce.
//
// So each value below is the SAME hex on both sides of the `dark:` pair. That
// looks like a mistake and is not; it is what makes the pair fixed.
//
// Kept out of `depools_status_tokens.dart` deliberately. That file is a status
// vocabulary and `bin/verify-design-contrast.py` parses it as one, checking every
// solid against `surface-container`. White paper against a light app surface is
// about 1.05:1 and would fail that check for the right reason applied to the
// wrong question: paper is never read against the app surface, it is read against
// ink. The verifier checks this file's own pairs in its PAPER section instead.
//
// Merged into the alias map in `lib/main.dart`:
//   WindThemeData(aliases: {...designAliases, ...depoolsStatusAliases,
//                           ...depoolsPaperAliases})

/// Print-surface className aliases: ink on paper, identical in both appearances.
///
/// `ink` is true black rather than DESIGN.md's near-black. That rule exists
/// because pure black on a screen reads as a hole punched in the surface; toner
/// on paper is simply black, and softening it here would misrepresent the output.
///
/// `ink-muted` is Apple's increased-contrast systemGray, which clears 4.5:1 on
/// white. It carries the second line of a label (location, team name), so it is
/// body text and gets the body-text threshold.
///
/// `ink-subtle` is not text. It draws the outline of an EMPTY cell on the sheet,
/// which is there so a user can see how much of a page they are about to waste
/// before committing paper. WCAG 1.4.11 does not apply to it for the same reason
/// it does not apply to the `border` token: a boundary that carries no state.
const Map<String, String> depoolsPaperAliases = <String, String>{
  'bg-paper': 'bg-[#FFFFFF] dark:bg-[#FFFFFF]',
  'bg-ink': 'bg-[#000000] dark:bg-[#000000]',
  'text-ink': 'text-[#000000] dark:text-[#000000]',
  'text-ink-muted': 'text-[#6C6C70] dark:text-[#6C6C70]',
  'bg-ink-muted': 'bg-[#6C6C70] dark:bg-[#6C6C70]',
  'border-color-ink-subtle': 'border-[#C7C7CC] dark:border-[#C7C7CC]',
};
