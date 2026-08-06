import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import 'choice_chip.dart';

/// Static variant-matrix preview for [ChoiceChip].
///
/// A grouped answer card as the assistant actually renders one: a suggested chip carrying
/// its own evidence, two plain alternatives, and an explicit skip. Every chip is a real
/// answer, which is what stops a card from becoming a question in disguise.
///
/// The second row is the same pattern for a date, where the skip is the honest one: a user
/// who does not know the expiry should be able to say so in one tap rather than inventing a
/// date to get past the card.
class ChoiceChipPreview extends StatelessWidget {
  /// Creates the ChoiceChip preview.
  const ChoiceChipPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const WDiv(
      className: 'flex flex-col gap-6 p-6',
      children: [
        WDiv(
          className: 'flex flex-col gap-3 p-4 rounded-lg bg-surface-container',
          children: [
            WDiv(
              className: 'flex flex-row wrap items-center gap-2',
              children: [
                ChoiceChip(
                  label: 'Buzdolabı',
                  evidence: '9 kez',
                  isSuggested: true,
                  semanticLabel: 'Buzdolabına koy',
                ),
                ChoiceChip(label: 'Kiler', semanticLabel: 'Kilere koy'),
                ChoiceChip(label: 'Diğer', semanticLabel: 'Başka bir konum seç'),
              ],
            ),
            WDiv(
              className: 'flex flex-row wrap items-center gap-2',
              children: [
                ChoiceChip(
                  label: '+5 gün',
                  evidence: 'raf ömrü',
                  isSuggested: true,
                  semanticLabel: 'Son kullanma tarihini beş gün sonrası yap',
                ),
                ChoiceChip(label: 'Tarih seç', semanticLabel: 'Takvimden tarih seç'),
                ChoiceChip(label: 'Bilinmiyor', semanticLabel: 'Son kullanma tarihini boş bırak'),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
