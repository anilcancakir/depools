/// The edge of an interactive control, as opposed to the edge of a card.
///
/// ### The measurement that forced this
///
/// `MSSwitch` in its off state renders a `#E7E6EC` track with a white thumb. On this palette's white
/// card the control's own edge measured **1.21:1**, and adding the `border` hairline took it to
/// **1.67:1**. WCAG 1.4.11 asks 3:1 for the boundary of a UI component, so both fail.
///
/// The switch is not exempt, and it is worth being precise about why, because a sibling case is.
/// W3C's Understanding of 1.4.11 says: "If a control has visible content (such as text or a
/// sufficiently contrasting icon), which helps users identify the presence of the control, then a
/// border or other indication of the overall boundary of the hit area is not required." That is
/// exactly why `MSButton`'s secondary fill measuring 1.31:1 against the same card is NOT a failure:
/// the word `Kopyala` carries full contrast and identifies the control.
///
/// A switch has no text and no icon. Its track and its thumb ARE the whole control, so there is
/// nothing to fall back on and the boundary has to carry it.
///
/// Dark mode hid this completely, which is why it survived three screens before a light-mode pass
/// caught it. Measured with a pixel scan, not judged by eye.
///
/// ### Why a separate token rather than reusing `border`
///
/// `border` is deliberately low contrast (1.52:1 in light) and DESIGN.md records why: it separates a
/// card from the page, WCAG 1.4.11 exempts decorative separators, and Apple's own `separator` at 29
/// percent opacity would fail a 3:1 test too. That reasoning is sound for a card edge and does not
/// transfer to a control edge, so the palette was using one token for two different jobs.
///
/// These values are Apple's `systemGray` in its increased-contrast forms, which keeps the
/// "everything here is Apple's own" property DESIGN.md rests on:
///
/// | | Value | vs `surface-container` | vs `surface` |
/// |---|---|---|---|
/// | light | `#8E8E93` | 3.26:1 (`#FFFFFF`) | 2.92:1 (`#F2F2F7`) |
/// | dark | `#7C7C80` | 4.09:1 (`#1C1C1E`) | 5.05:1 (`#000000`) |
///
/// Those four numbers come from `bin/verify-design-contrast.py`, not from this comment: a first pass
/// wrote them from memory and two were wrong.
///
/// The light value clears 3:1 on a card and lands just under it on the page, at 2.92:1. That is a
/// real gap rather than a rounding one, and it is accepted for a stated reason: every switch in this
/// app sits on a card, because a bare toggle on the page surface is not a pattern the design uses.
/// `bin/verify-design-contrast.py` checks all four numbers, so if a switch ever does land on the page
/// surface the build says so instead of the gap being rediscovered by eye.
///
/// ### Why this is a hand-authored supplement
///
/// `design:sync` emits a FIXED table of 17 aliases and silently drops any other token in DESIGN.md's
/// frontmatter: adding `border-strong` there produced no alias at all and only a `design:lint`
/// warning that it was unused. That is the same silent-drop DESIGN.md already records for
/// `text-accent`. Extending the table is a change to `magic`'s own command and therefore a PR in
/// that repository, so the token lives here and is merged in `main.dart`, exactly like the status,
/// paper and overlay supplements.
///
/// The alias key is the WHOLE token as it appears in a `className`. Wind's expander matches a
/// complete token against a key, which is why `border-bg-primary` drops silently: write
/// `border-color-control` and nothing else.
library;

/// Aliases merged into the Wind theme in `main.dart`.
const Map<String, String> depoolsControlAliases = <String, String>{
  'border-color-control': 'border-[#8E8E93] dark:border-[#7C7C80]',
};
