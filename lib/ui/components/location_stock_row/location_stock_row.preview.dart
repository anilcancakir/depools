import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import 'location_stock_row.dart';

/// Static variant-matrix preview for [LocationStockRow].
///
/// The first card is the hard case: one product split across two nested locations
/// with different expiry pressure at each, which is the answer "you have 5" would
/// have hidden. The long path in the second card exercises truncation.
class LocationStockRowPreview extends StatelessWidget {
  /// Creates the LocationStockRow preview.
  const LocationStockRowPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const WDiv(
      className: 'flex flex-col gap-6 p-6',
      children: [
        WDiv(
          className: 'flex flex-col gap-1 p-4 rounded-lg bg-surface-container',
          children: [
            WText('Pınar Süt Tam Yağlı 1 lt', className: 'text-base font-semibold text-fg'),
            WText('Toplam 5 adet, iki konumda', className: 'text-xs text-fg-muted'),
            LocationStockRow(
              path: 'Mutfak › Buzdolabı',
              quantity: '3',
              unit: 'adet',
              lotsLabel: '3 parti',
              expiryLabel: 'Süresi geçti',
              daysUntilExpiry: -1,
            ),
            LocationStockRow(
              path: 'Kiler › Raf 2',
              quantity: '2',
              unit: 'adet',
              lotsLabel: '1 parti',
              expiryLabel: '9 gün',
              daysUntilExpiry: 9,
            ),
          ],
        ),
        WDiv(
          className: 'flex flex-col gap-1 p-4 rounded-lg bg-surface-container',
          children: [
            WText('Uzun yol ve boş konum', className: 'text-base font-semibold text-fg'),
            LocationStockRow(
              path: 'Depo › Koridor B › Raf 14 › Kutu 3 › Alt Bölme',
              quantity: '18,50',
              unit: 'kg',
              lotsLabel: '2 parti',
            ),
            LocationStockRow(
              path: 'Derin Dondurucu',
              quantity: '0',
              unit: 'kg',
              lotsLabel: 'parti yok',
              isEmpty: true,
            ),
          ],
        ),
      ],
    );
  }
}
