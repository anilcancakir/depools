import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import 'option_row.recipe.dart';

/// **OptionRow**
///
/// One full-width choice in a picker: a label, optionally why it is suggested, optionally a
/// figure on the right.
///
/// **Extracted at the fourth caller, not the first.** The stock-move sheet had two of these,
/// the stock-in sheet a third and the label screen a fourth, each repeating the same
/// className and each one place the "every option gets a fill" rule could drift. A fifth
/// (the draft form's field editor) is what tipped it: the rule says wait for the third
/// concrete caller before extracting, and by then there were four.
///
/// The suggestion line is `suggestionReason` rather than a general-purpose note, because
/// that is what all four callers use it for. A neutral note would be speculation until
/// something actually needs one.
@immutable
class OptionRow extends StatelessWidget {
  /// The already-localised label.
  final String label;

  /// Why this option is suggested, already localised. Rendered under the label in the
  /// `ai` tone, because it is what the app inferred rather than what the user chose.
  final String? suggestionReason;

  /// A figure on the right: a quantity, a page count, whatever the picker compares on.
  final Widget? trailing;

  /// Whether the label is machine text: a serial, a code, anything compared character by
  /// character against a physical object.
  final bool isMono;

  /// Whether this is the current choice.
  final bool isSelected;

  /// What choosing it does, spelled out for a screen reader.
  final String semanticLabel;

  /// Called when it is chosen.
  final VoidCallback? onTap;

  /// Creates an [OptionRow].
  const OptionRow({
    super.key,
    required this.label,
    required this.semanticLabel,
    this.suggestionReason,
    this.trailing,
    this.isMono = false,
    this.isSelected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final slots = optionRowRecipe()(
      variants: {'type': isMono ? 'mono' : 'text', 'state': isSelected ? 'selected' : 'idle'},
    );

    return WAnchor(
      onTap: onTap,
      semanticLabel: semanticLabel,
      child: WDiv(
        className: slots['root'],
        states: isSelected ? const {'selected'} : const {},
        children: [
          // The radio is what says "pick one of these" in an appearance-independent way.
          // The fill cannot: raised is lighter in dark and whiter in light, so a single
          // fill token reads as tappable in one mode and disabled in the other.
          WDiv(
            className: slots['radio'],
            child: WDiv(className: slots['dot']),
          ),
          WDiv(
            className: slots['body'],
            children: [
              WText(label, className: slots['label']),
              if (suggestionReason != null) WText(suggestionReason!, className: slots['reason']),
            ],
          ),
          if (trailing != null) WDiv(className: slots['trailing'], child: trailing),
        ],
      ),
    );
  }
}
