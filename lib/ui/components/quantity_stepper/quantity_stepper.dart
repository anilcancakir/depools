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
/// **One border around the whole control.** The group owns it; the buttons and the field sit
/// inside with hairline dividers between them. Three earlier shapes and why each failed are in
/// the recipe, including the one that needed a raw `WInput` and threw from the preview harness.
///
/// **A button with no callback has no pointer cursor, and that is correct.** `WAnchor` gives the
/// hand only when it actually has a gesture, so a stepper built without `onIncrement` is inert
/// and says so. It also means a preview that omits the callbacks is not testing the hover
/// behaviour, which is how a missing cursor got reported against working code.
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

  /// The unit this quantity is counted in, rendered inside the field.
  ///
  /// Inside rather than beside: a unit floating next to the control is a separate object, and two
  /// of them next to two boxes read as two independent quantities. `12 piece` is one thing.
  final String? unit;

  /// The opened unit's amount, as typed.
  ///
  /// Non-null [remainderUnit] is what makes the second segment appear at all. A product with
  /// nothing finer inside it has no remainder to state, and a second field measuring the same unit
  /// as the first is a duplicate: measured on the demo tenant's milk, base `l` with a content of
  /// `1 l`, where both labels read `l`.
  final String? remainderValue;

  /// The opened unit's unit, for example `ml`. Null hides the segment.
  final String? remainderUnit;

  /// What the empty remainder field says it is for.
  ///
  /// **The field names itself while it is empty**, which is when the user needs to know. The
  /// alternative was a caption above the segment, and it needs a spacer matched to the first
  /// segment's width to sit over the right one: a fixed number that goes wrong the moment a digit
  /// is added. Once the field holds a value the unit suffix and the divider carry the meaning.
  final String? remainderPlaceholder;

  /// Called as the opened-unit amount changes.
  final ValueChanged<String>? onRemainderChanged;

  /// Creates a [QuantityStepper].
  const QuantityStepper({
    super.key,
    required this.semanticName,
    this.value,
    this.placeholder = '—',
    this.onChanged,
    this.onDecrement,
    this.onIncrement,
    this.unit,
    this.remainderValue,
    this.remainderUnit,
    this.remainderPlaceholder,
    this.onRemainderChanged,
  });

  @override
  Widget build(BuildContext context) {
    final slots = quantityStepperRecipe()();

    return WDiv(
      className: slots['root'],
      children: [
        _button(slots, slots['left'], _decrementIcon, Lang.get('components.quantity_stepper.decrement', {'name': semanticName}), onDecrement),
        WDiv(
          className: slots['field'],
          child: MSInput(
            className: slots['input'],
            value: value ?? '',
            placeholder: placeholder,
            type: InputType.number,
            onChanged: onChanged,
            suffix: unit == null ? null : WText(unit!, className: slots['unit']),
          ),
        ),
        _button(slots, slots['right'], _incrementIcon, Lang.get('components.quantity_stepper.increment', {'name': semanticName}), onIncrement),
        // The opened unit, in the same control. No stepper on it: the step is one and a remainder is
        // a measured amount, so plus-one-millilitre is a control that cannot reach most of its own
        // values. That reasoning is why the segment is a bare field rather than a second stepper.
        if (remainderUnit != null)
          WDiv(
            className: slots['remainder'],
            child: MSInput(
              className: slots['input'],
              value: remainderValue ?? '',
              placeholder: remainderPlaceholder ?? placeholder,
              type: InputType.number,
              onChanged: onRemainderChanged,
              suffix: WText(remainderUnit!, className: slots['unit']),
            ),
          ),
      ],
    );
  }

  /// One adjustment button, borderless so the field is the only bordered box.
  ///
  /// `WAnchor` gives it the pointer cursor on web for free, which is what makes it read as
  /// pressable there.
  /// One half of the control. `WAnchor` gives it the pointer cursor on web whenever it has a
  /// gesture, which is what makes it read as pressable there, and correctly withholds it when
  /// there is nothing to press.
  Widget _button(
    Map<String, String> slots,
    String? boxClass,
    IconData icon,
    String label,
    VoidCallback? onTap,
  ) {
    return WAnchor(
      onTap: onTap,
      semanticLabel: label,
      child: WDiv(
        className: boxClass,
        child: WIcon(icon, className: slots['icon']),
      ),
    );
  }
}
