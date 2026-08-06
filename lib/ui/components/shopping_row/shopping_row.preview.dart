import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import 'shopping_row.dart';

/// Static variant-matrix preview for [ShoppingRow].
///
/// All five reasons plus a ticked line. Read the reason column top to bottom: the claim
/// changes SHAPE as the data thins out, from a number, to a bucket, to a bare ratio with no
/// time in it at all. That progression is the uncertainty display (D46), and it is the
/// whole reason this component exists rather than a generic checklist row.
///
/// What to check: only the two reasons with a deadline carry a tone. A list where every
/// line is coloured has no priority in it, and `forecasting.md` puts the product's
/// credibility on this column being trustworthy rather than loud.
class ShoppingRowPreview extends StatelessWidget {
  /// Creates the ShoppingRow preview.
  const ShoppingRowPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const WDiv(
      className: 'flex flex-col gap-6 p-6',
      children: [
        WDiv(
          className: 'flex flex-col gap-1 p-4 rounded-lg bg-surface-container',
          children: [
            ShoppingRow(
              name: 'Pınar Süt Tam Yağlı 1 lt',
              amount: 2,
              formatted: '2',
              reason: ShoppingReason.runningOut,
              reasonDetail: '2 günlük kaldı',
            ),
            ShoppingRow(
              name: 'Yoğurt 2 kg',
              amount: 1,
              formatted: '1',
              reason: ShoppingReason.expiring,
              reasonDetail: 'Açılmış kap · 3 gün ömür',
            ),
            ShoppingRow(
              name: 'Un',
              amount: 1,
              formatted: '1',
              unit: 'kg',
              reason: ShoppingReason.roughlyDue,
              reasonDetail: 'Yaklaşık bir hafta · geçmiş az',
            ),
            ShoppingRow(
              name: 'Tornavida Seti PH2',
              amount: 2,
              formatted: '2',
              reason: ShoppingReason.belowTarget,
              reasonDetail: 'Hedefin altında · 0 / 2 adet',
            ),
            ShoppingRow(
              name: 'Bulaşık deterjanı',
              amount: 1,
              formatted: '1',
              reason: ShoppingReason.manual,
              reasonDetail: 'Elle eklendi',
            ),
            ShoppingRow(
              name: 'Ayçiçek Yağı 5 lt',
              amount: 1,
              formatted: '1',
              reason: ShoppingReason.belowTarget,
              reasonDetail: 'Hedefin altında · 1 / 3 adet',
              isChecked: true,
            ),
          ],
        ),
      ],
    );
  }
}
