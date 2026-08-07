import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import 'quantity_stepper.dart';

/// Static variant-matrix preview for [QuantityStepper].
///
/// Three states: a value typed, an empty field whose dash means "not answered", and an
/// explicit zero. The last two are the pair that must not look alike on a count sheet, where
/// an unanswered row is left untouched and a zero writes the balance off.
///
/// What to check: one border around the whole control, and the buttons and field reading as
/// ENABLED in light mode. That is why they carry the card tone rather than the input tone, which
/// on a white card is darker than its container and reads as disabled.
///
/// **The callbacks are wired here on purpose.** `WAnchor` gives a pointer cursor only when it
/// actually has a gesture, so a preview built without them shows no hand on hover and looks like
/// a missing cursor in working code. It was reported that way once.
class QuantityStepperPreview extends StatelessWidget {
  /// Creates the QuantityStepper preview.
  const QuantityStepperPreview({super.key});

  static void _noop(String _) {}
  static void _noopVoid() {}

  @override
  Widget build(BuildContext context) {
    return WDiv(
      className: 'flex flex-col gap-6 p-6',
      children: [
        WDiv(
          className: 'flex flex-col gap-3 p-4 rounded-lg bg-surface-container',
          children: [
            QuantityStepper(
              semanticName: 'Miktar',
              value: '12',
              onChanged: _noop,
              onDecrement: _noopVoid,
              onIncrement: _noopVoid,
            ),
            QuantityStepper(
              semanticName: 'Sayım',
              onChanged: _noop,
              onDecrement: _noopVoid,
              onIncrement: _noopVoid,
            ),
            QuantityStepper(
              semanticName: 'Sayım',
              value: '0',
              onChanged: _noop,
              onDecrement: _noopVoid,
              onIncrement: _noopVoid,
            ),
          ],
        ),
      ],
    );
  }
}
