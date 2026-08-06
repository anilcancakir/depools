import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import 'choice_chip.recipe.dart';

/// **ChoiceChip**
///
/// One tap-answer in an assistant's grouped question card.
///
/// **Every chip is a real, likely answer including the skip**, which is `ai-design.md`'s
/// rule for these cards. A chip that opens another question is a question wearing a chip's
/// clothes, and the same doc caps a capture at one follow-up card.
///
/// The count on a suggested chip is the explanation, the same way it is everywhere else in
/// this app: `Buzdolabı · 9 kez` says why it is suggested without a second sentence, and it
/// is a claim the user can disagree with.
@immutable
class ChoiceChip extends StatelessWidget {
  /// The already-localised label.
  final String label;

  /// The already-localised evidence, for example `'9 kez'`. Rendered inline after the
  /// label, in a lighter tone.
  final String? evidence;

  /// Whether this is the suggested answer.
  final bool isSuggested;

  /// What tapping it does, spelled out for a screen reader. Required rather than derived,
  /// because a chip in an assistant card can mean anything and a generic label is what
  /// makes an accessible control useless.
  final String semanticLabel;

  /// Called when it is tapped.
  final VoidCallback? onTap;

  /// Creates a [ChoiceChip].
  const ChoiceChip({
    super.key,
    required this.label,
    required this.semanticLabel,
    this.evidence,
    this.isSuggested = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return WAnchor(
      onTap: onTap,
      semanticLabel: semanticLabel,
      child: WDiv(
        className: choiceChipRecipe()(variants: {'emphasis': isSuggested ? 'suggested' : 'plain'}),
        children: [
          WText(label, className: 'text-sm font-medium text-fg'),
          if (evidence != null) WText(evidence!, className: 'text-xs text-fg-muted'),
        ],
      ),
    );
  }
}
