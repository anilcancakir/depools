import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import 'lot_row.dart';

/// Static variant-matrix preview for [LotRow].
///
/// Rendered as the hard case on purpose: one product, three lots, three different
/// dates with one already expired, plus a depleted fourth. This is the shape a
/// single expiry field on the product could never express, and the reason the
/// schema carries lots at all.
class LotRowPreview extends StatelessWidget {
  /// Creates the LotRow preview.
  const LotRowPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const WDiv(
      className: 'flex flex-col gap-6 p-6',
      children: [
        WDiv(
          className: 'flex flex-col gap-1 p-4 rounded-lg bg-surface-container',
          children: [
            WText('Pınar Süt Tam Yağlı 1 lt', className: 'text-base font-semibold text-fg'),
            WText('Buzdolabı · 3 parti', className: 'text-xs text-fg-muted'),
            LotRow(
              remainingAmount: 0.5,
              remaining: '500',
              unit: 'ml',
              isOpen: true,
              expiryLabel: '2 gün',
              daysUntilExpiry: 2,
              openedLabel: '5 Ağu açıldı · kutuda 12 Ağu yazıyor',
            ),
            LotRow(
              remainingAmount: 1,
              remaining: '1',
              unit: 'adet',
              expiryLabel: 'Süresi geçti',
              daysUntilExpiry: -1,
              receivedLabel: '28 Tem alındı',
            ),
            LotRow(
              remainingAmount: 1,
              remaining: '1',
              unit: 'adet',
              expiryLabel: '2 gün',
              daysUntilExpiry: 2,
              receivedLabel: '3 Ağu alındı',
              lotCode: 'L2408-33',
            ),
            LotRow(
              remainingAmount: 1,
              remaining: '1',
              unit: 'adet',
              expiryLabel: '9 gün',
              daysUntilExpiry: 9,
              receivedLabel: '5 Ağu alındı',
            ),
            LotRow(
              remainingAmount: 0,
              remaining: '0',
              unit: 'adet',
              expiryLabel: '12 Tem',
              daysUntilExpiry: -24,
              receivedLabel: '8 Tem alındı',
              isDepleted: true,
            ),
          ],
        ),
        WDiv(
          className: 'flex flex-col gap-1 p-4 rounded-lg bg-surface-container',
          children: [
            WText('Ayçiçek Yağı 5 lt', className: 'text-base font-semibold text-fg'),
            WText('Tarihsiz bir parti hiç rozet göstermez', className: 'text-xs text-fg-muted'),
            LotRow(remainingAmount: 2, remaining: '2', unit: 'adet', receivedLabel: '1 Ağu alındı'),
          ],
        ),
      ],
    );
  }
}
