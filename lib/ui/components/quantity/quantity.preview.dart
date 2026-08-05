import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import 'quantity.dart';

/// Static variant-matrix preview for [Quantity].
///
/// The right-hand column is the reason this component exists: three values of
/// different digit widths stacked, so a misaligned column is visible at a glance.
/// If those decimal separators do not sit on one vertical line, `font-mono` is not
/// resolving to Geist Mono.
class QuantityPreview extends StatelessWidget {
  /// Creates the Quantity preview.
  const QuantityPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const WDiv(
      className: 'flex flex-col gap-6 p-6',
      children: [
        WDiv(
          className: 'flex flex-row items-end gap-6',
          children: [
            Quantity(amount: 3, formatted: '3', unit: 'adet', size: QuantitySize.sm),
            Quantity(amount: 18.5, formatted: '18,50', unit: 'kg', size: QuantitySize.md),
            Quantity(amount: 1240, formatted: '1.240,00', unit: 'kg', size: QuantitySize.lg),
          ],
        ),
        WDiv(
          className: 'flex flex-row items-center gap-6',
          children: [
            Quantity(amount: 0, formatted: '0', unit: 'kg'),
            Quantity(amount: 2, formatted: '2', unit: 'koli', tone: QuantityTone.muted),
            Quantity(amount: 12, formatted: '12', unit: 'adet', tone: QuantityTone.inbound),
            Quantity(amount: -1, formatted: '-1', unit: 'adet', tone: QuantityTone.waste),
          ],
        ),
        WDiv(
          className: 'flex flex-col items-end gap-1 p-3 rounded-md bg-surface-container-high',
          children: [
            Quantity(amount: 1240, formatted: '1.240,00', unit: 'kg'),
            Quantity(amount: 18.5, formatted: '18,50', unit: 'kg'),
            Quantity(amount: 111.11, formatted: '111,11', unit: 'kg'),
            Quantity(amount: 0.8, formatted: '0,80', unit: 'kg'),
          ],
        ),
      ],
    );
  }
}
