import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import 'quantity_stepper.dart';

/// Static variant-matrix preview for [QuantityStepper].
///
/// Three states: a value typed, an empty field whose dash means "not answered", and an
/// explicit zero. The last two are the pair that must not look alike on a count sheet, where
/// an unanswered row is left untouched and a zero writes the balance off.
///
/// What to check: the buttons and the field must read as ENABLED in light mode. That is why
/// they carry the card tone and a hairline rather than the input tone, which on a white card
/// is darker than its container and reads as disabled.
class QuantityStepperPreview extends StatelessWidget {
  /// Creates the QuantityStepper preview.
  const QuantityStepperPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const WDiv(
      className: 'flex flex-col gap-6 p-6',
      children: [
        WDiv(
          className: 'flex flex-col gap-3 p-4 rounded-lg bg-surface-container',
          children: [
            QuantityStepper(semanticName: 'Miktar', value: '12'),
            QuantityStepper(semanticName: 'Sayım'),
            QuantityStepper(semanticName: 'Sayım', value: '0'),
          ],
        ),
      ],
    );
  }
}
