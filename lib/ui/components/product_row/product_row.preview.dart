import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import 'product_row.dart';

/// Static variant-matrix preview for [ProductRow].
///
/// The list a cafe owner actually opens: something already expired, something with
/// days left, something plain, something out of stock, and a name long enough to
/// prove it truncates rather than overflowing. If the quantity column does not line
/// up down the right edge, `Quantity`'s mono is not resolving.
class ProductRowPreview extends StatelessWidget {
  /// Creates the ProductRow preview.
  const ProductRowPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const WDiv(
      className: 'flex flex-col gap-6 p-6',
      children: [
        WDiv(
          className: 'flex flex-col gap-1 p-4 rounded-lg bg-surface-container',
          children: [
            ProductRow(
              name: 'Pınar Süt Tam Yağlı 1 lt',
              meta: 'Pınar · Buzdolabı, Kiler',
              amount: 5,
              formatted: '5',
              unit: 'adet',
              expiryLabel: 'Süresi geçti',
              daysUntilExpiry: -1,
            ),
            ProductRow(
              name: 'Bulgur',
              meta: 'Duru · Çekmece 2',
              amount: 0.8,
              formatted: '0,80',
              unit: 'kg',
              expiryLabel: '2 gün',
              daysUntilExpiry: 2,
            ),
            ProductRow(
              name: 'Ayçiçek Yağı 5 lt',
              meta: 'Yudum · Kiler › Raf 2',
              amount: 2,
              formatted: '2',
              unit: 'adet',
            ),
            ProductRow(
              name: 'Kıyma',
              meta: 'Dana · Derin dondurucu',
              amount: 0,
              formatted: '0',
              unit: 'kg',
            ),
            ProductRow(
              name: 'Zeytinyağlı Yaprak Sarma Konservesi 400 gramlık teneke kutu',
              meta: 'Tariş · Depo › Koridor B › Raf 14 › Kutu 3',
              amount: 1240,
              formatted: '1.240,00',
              unit: 'kg',
              expiryLabel: '38 gün',
              daysUntilExpiry: 38,
            ),
          ],
        ),
      ],
    );
  }
}
