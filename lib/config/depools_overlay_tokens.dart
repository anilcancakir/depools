/// Overlay strokes: the two colours a border can use when its background is a PHOTOGRAPH.
///
/// ### Why these are not semantic aliases
///
/// Every token `design:sync` emits carries a `dark:` pair, because the surface behind it is one the
/// app controls and it changes with the appearance. These do not. A barcode viewfinder is drawn over
/// a live camera feed and a shelf-photo region box is drawn over a still image, and neither gets
/// lighter because the user turned dark mode on. So both sides of the pair hold the same value, the
/// same way `depools_paper_tokens.dart` pins a printed sheet's white.
///
/// ### Why there are TWO of them, and why that is a proof rather than a preference
///
/// DESIGN.md deferred this token, and its reasoning was right for the thing it was considering:
/// picking one hex against a placeholder rather than a real photograph is guessing at the thing
/// that matters, because the correct value depends on the image.
///
/// A single stroke cannot escape that. A PAIR can, and the escape is arithmetic. For a background
/// of relative luminance L, contrast to white is `1.05 / (L + 0.05)` and contrast to black is
/// `(L + 0.05) / 0.05`. The two curves cross at L = 0.179, where both equal 4.58:1, and away from
/// the crossing one of them only grows. So for ANY background whatsoever, the better of a
/// black-and-white pair is at least **4.58:1**, comfortably above the 3:1 that WCAG 1.4.11 asks of
/// a UI component boundary. `bin/verify-design-contrast.py` checks that floor rather than trusting
/// this comment.
///
/// Drawn as two concentric strokes (outer ink, inner paper), so whatever the photograph does under
/// them, the boundary is carried by whichever one currently contrasts. This is what browser element
/// highlighters, screenshot region pickers and camera viewfinders all do, and for the same reason.
///
/// ### Not `#000000` and `#FFFFFF` exactly
///
/// Pure black beside pure white on a photograph reads as a rendering artefact rather than as part of
/// the interface, the same way DESIGN.md rejects pure black text on a saturated fill. These are
/// Apple's own darkest and lightest system greys, which keep the pair reading as UI. The softening
/// costs some of the floor and the cost is measured, not estimated: **3.91:1** at L = 0.191, down
/// from the ideal pair's 4.58:1 and still clear of 3:1. The two strokes are 15.25:1 against each
/// other, so the boundary between them is never the weak link.
library;

/// The two overlay strokes, merged into the Wind alias map in `main.dart`.
///
/// `design:sync` does not emit these, exactly as it does not emit the status or paper families;
/// they are hand-authored supplements and DESIGN.md documents all three.
const Map<String, String> depoolsOverlayAliases = <String, String>{
  /// The outer stroke. Apple `systemGray6` dark, the darkest neutral in the system palette.
  'border-color-overlay-ink': 'border-[#1C1C1E] dark:border-[#1C1C1E]',

  /// The inner stroke. Apple `systemGray6` light, the lightest neutral in the system palette.
  'border-color-overlay-paper': 'border-[#F2F2F7] dark:border-[#F2F2F7]',
};
