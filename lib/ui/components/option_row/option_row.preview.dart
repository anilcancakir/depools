import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../quantity/quantity.dart';
import 'option_row.dart';

/// Static variant-matrix preview for [OptionRow].
///
/// Two groups, because the component serves two shapes: a location picker where the
/// suggestion carries its own count, and a comparison list where each row ends in a figure.
///
/// The thing to check is that the UNSELECTED rows still read as choices. Every option has a
/// fill; a group where only the chosen row has a background reads as one highlight among
/// labels, which is the correction that produced this rule.
class OptionRowPreview extends StatelessWidget {
  /// A tear-off rather than a closure, so every `const` in this file survives.
  ///
  /// The callbacks are here at all because a control previewed WITHOUT one is a dead
  /// control: `WAnchor` withholds the pointer cursor when it has no gesture, so the
  /// catalog showed no hand on hover and it was reported as a missing cursor in code
  /// that works. Eleven previews had this.
  static void _noop() {}

  /// Creates the OptionRow preview.
  const OptionRowPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const WDiv(
      className: 'flex flex-col gap-6 p-6',
      children: [
        WDiv(
          className: 'flex flex-col gap-1 p-4 rounded-lg bg-surface-container',
          children: [
            OptionRow(
              label: 'Mutfak › Buzdolabı',
              suggestionReason: 'Önerilen · buraya 9 kez konuldu',
              isSelected: true,
              semanticLabel: 'Mutfak buzdolabı konumunu seç',
            onTap: _noop),
            OptionRow(label: 'Kiler › Raf 2', semanticLabel: 'Kiler raf 2 konumunu seç', onTap: _noop),
            OptionRow(label: 'Depo › Raf A', semanticLabel: 'Depo raf A konumunu seç', onTap: _noop),
          ],
        ),
        WDiv(
          className: 'flex flex-col gap-1 p-4 rounded-lg bg-surface-container',
          children: [
            OptionRow(
              label: "A4 · 8'li · 105×70 mm",
              isSelected: true,
              semanticLabel: 'A4 sekizli yerleşimi seç',
              trailing: Quantity(amount: 3, formatted: '3', unit: 'sayfa', size: QuantitySize.sm),
            onTap: _noop),
            OptionRow(
              label: "A4 · 24'lü · 70×37 mm",
              semanticLabel: 'A4 yirmi dörtlü yerleşimi seç',
              trailing: Quantity(amount: 1, formatted: '1', unit: 'sayfa', size: QuantitySize.sm),
            onTap: _noop),
          ],
        ),
        // The informational state, which is a real variant rather than a disabled one: settings has
        // a row whose own note says "Always on", and with no `onTap` the component drops its anchor
        // so the row reads as a statement instead of as a button that swallows a tap.
        WDiv(
          className: 'flex flex-col gap-1 p-4 rounded-lg bg-surface-container',
          children: [
            OptionRow(
              label: 'Yaklaşan tarihler',
              description: 'Her zaman açık. Onsuz özetin söyleyecek bir şeyi kalmaz.',
              isSelected: true,
              semanticLabel: 'Yaklaşan tarihler her zaman açık',
            ),
          ],
        ),
      ],
    );
  }
}
