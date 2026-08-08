import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import 'setup_step.dart';

/// Static variant-matrix preview for [SetupStep].
///
/// Renders all three states in the order a real checklist reaches them, so the two things worth
/// checking are visible side by side: the markers share one x and one size across a tick and two
/// numbers, and the three states are told apart by glyph and weight rather than by tone alone.
///
/// The callbacks are wired even though they do nothing. `WAnchor` gives the pointer cursor only
/// when it actually has a gesture, so a callback-less preview shows no hand on hover and reads as
/// a missing cursor in working code, which is how one was reported.
class SetupStepPreview extends StatelessWidget {
  /// Creates the SetupStep preview.
  const SetupStepPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return WDiv(
      className: 'flex flex-col gap-6 p-6',
      children: <Widget>[
        WDiv(
          className: 'flex flex-col rounded-lg border border-color-border bg-surface-container p-4',
          children: <Widget>[
            SetupStep(
              marker: '1',
              title: 'Konumları tanımlayın',
              description: 'Bir ürünün nerede durduğu bilinmeden sayım yapılamaz.',
              state: SetupStepState.done,
              actionLabel: 'Konum ekle',
              onAction: () {},
            ),
            SetupStep(
              marker: '2',
              title: 'İlk ürünleri ekleyin',
              description: 'Barkodu okutun, fotoğrafını çekin veya elle girin.',
              state: SetupStepState.current,
              actionLabel: 'Ürün ekle',
              onAction: () {},
            ),
            SetupStep(
              marker: '3',
              title: 'Hedef seviye belirleyin',
              description: 'Hedefi olmayan ürün azalanlar listesinde hiç görünmez.',
              actionLabel: 'Ürünlere git',
              onAction: () {},
            ),
          ],
        ),
      ],
    );
  }
}
