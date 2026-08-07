import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart' show MSInput;
import 'quantity_stepper.recipe.dart';

/// **QuantityStepper**
///
/// A typed quantity with a minus and a plus beside it.
///
/// **Both halves are needed and neither is enough.** Tapping plus twelve times to reach twelve
/// is why a bare stepper fails on a stock screen; typing 3 when you meant 4 is why a bare field
/// fails on a shelf, where the user is holding something in their other hand. So the field is
/// the primary control and the buttons are the adjustment.
///
/// **The step is one, so the unit has to be countable.** An opened remainder is a measured
/// amount where plus-one-millilitre means nothing, so a stepper does not belong on one: that
/// field stays typed. A stepper whose step does not match the granularity of its unit is a
/// control that cannot reach most of its own values.
///
/// **Exactly one bordered box.** The field keeps its border and the buttons flank it with none,
/// which is Material's outlined-field-with-icons shape. Two earlier attempts are recorded in the
/// recipe: three separately bordered boxes read as three unrelated controls, and moving the
/// border to the group meant using a raw `WInput`, which needs an `Overlay` ancestor and threw
/// from inside the preview harness.
///
/// Every part has a fixed width. This repeats down a list, and a list of repeating controls is
/// a table whatever it is built from.
@immutable
class QuantityStepper extends StatelessWidget {
  static const IconData _decrementIcon = Icons.remove;
  static const IconData _incrementIcon = Icons.add;

  /// The value as typed, or null when the field is empty.
  final String? value;

  /// What an empty field shows. A dash where empty means "not answered", a zero where it
  /// means zero: the caller knows which, and on the count sheet the difference is the whole
  /// design.
  final String placeholder;

  /// What the control is for, so a screen reader can name the two buttons.
  final String semanticName;

  /// Called as the typed value changes.
  final ValueChanged<String>? onChanged;

  /// Called when minus is tapped.
  final VoidCallback? onDecrement;

  /// Called when plus is tapped.
  final VoidCallback? onIncrement;

  /// Creates a [QuantityStepper].
  const QuantityStepper({
    super.key,
    required this.semanticName,
    this.value,
    this.placeholder = '—',
    this.onChanged,
    this.onDecrement,
    this.onIncrement,
  });

  @override
  Widget build(BuildContext context) {
    final slots = quantityStepperRecipe()();

    return WDiv(
      className: slots['root'],
      children: [
        _button(slots, _decrementIcon, '$semanticName, bir azalt', onDecrement),
        WDiv(
          className: slots['field'],
          child: MSInput(
            // Card tone over the recipe's input tone: on a white card the input tone is
            // darker than its container and reads as disabled. `text-center` because the
            // value sits between two buttons and a left-aligned number looks detached from
            // the plus.
            className: 'bg-surface-container text-center',
            value: value ?? '',
            placeholder: placeholder,
            type: InputType.number,
            onChanged: onChanged,
          ),
        ),
        _button(slots, _incrementIcon, '$semanticName, bir artır', onIncrement),
      ],
    );
  }

  /// One adjustment button, borderless so the field is the only bordered box.
  ///
  /// `WAnchor` gives it the pointer cursor on web for free, which is what makes it read as
  /// pressable there.
  Widget _button(Map<String, String> slots, IconData icon, String label, VoidCallback? onTap) {
    return WAnchor(
      onTap: onTap,
      semanticLabel: label,
      child: WDiv(
        className: slots['button'],
        child: WIcon(icon, className: slots['icon']),
      ),
    );
  }
}
