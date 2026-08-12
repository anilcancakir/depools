import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import 'setup_step.recipe.dart';

export 'setup_step.recipe.dart' show SetupStepState;

/// **SetupStep**
///
/// One numbered step in a first-run checklist: a marker, a title, a line saying what the step gets
/// you, and an action.
///
/// ### It says what the step BUYS, not what it is
///
/// `Konumları tanımlayın` alone is an instruction with no reason attached, and a first-run screen
/// is exactly where a user decides whether the work is worth it. The description carries the
/// payoff (`Bir ürünün nerede durduğunu bilmeden sayım yapılamaz`), because someone who has just
/// signed up has no model of the product yet and will not infer it.
///
/// ### A finished step stays on screen
///
/// Done steps are kept rather than removed, for the same reason the receipt review keeps its
/// resolved group: a list that shrinks as you work gives no sense of how much is left, and a user
/// who returns to a half-done setup needs to see what they already did before they can tell what
/// is next.
///
/// ```dart
/// SetupStep(
///   marker: '1',
///   title: 'Konumları tanımlayın',
///   description: 'Bir ürünün nerede durduğunu bilmeden sayım yapılamaz.',
///   state: SetupStepState.current,
///   actionLabel: 'Konum ekle',
///   onAction: () => MagicRoute.to('/locations'),
/// )
/// ```
@immutable
class SetupStep extends StatelessWidget {
  static const IconData _doneIcon = Icons.check;

  /// The step number, shown when the step is not [SetupStepState.done].
  final String marker;

  /// What the step is, imperative because the user is being asked to do it.
  final String title;

  /// What the step gets them, in one line.
  final String description;

  /// Where the step stands.
  final SetupStepState state;

  /// The action's label. Absent on a done step, which has nothing left to ask.
  final String? actionLabel;

  /// Called when the action is taken.
  final VoidCallback? onAction;

  /// Creates a [SetupStep].
  const SetupStep({
    super.key,
    required this.marker,
    required this.title,
    required this.description,
    this.state = SetupStepState.pending,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final Map<String, String> slots = setupStepRecipe()(
      variants: <String, String>{kSetupStepStateAxis: state.name},
    );
    final bool isDone = state == SetupStepState.done;

    return WDiv(
      className: slots['root'],
      children: <Widget>[
        WDiv(
          className: slots['marker'],
          // The glyph changes, the box does not. See the recipe's docblock: a conditional leading
          // icon is only safe when it cannot move the text beside it.
          child: isDone
              ? WIcon(_doneIcon, className: 'size-4 ${slots['markerText']}')
              : WText(marker, className: slots['markerText']),
        ),
        WDiv(
          className: slots['body'],
          children: <Widget>[
            WText(title, className: slots['title']),
            WText(description, className: slots['description']),
            // The action is part of the step rather than a trailing column, because the step's
            // body is where the reading ends and a 44pt target on the right edge of a phone is
            // the hardest place on the screen to reach.
            if (!isDone && actionLabel != null)
              WDiv(
                className: 'pt-1',
                child: WAnchor(
                  onTap: onAction,
                  semanticLabel: actionLabel,
                  child: WText(
                    actionLabel!,
                    className: 'text-sm font-medium text-primary',
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
