import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../expiry_badge/expiry_badge.dart';
import 'stock_badge.dart';

/// Static variant-matrix preview for [StockBadge].
///
/// Shown beside [ExpiryBadge] on purpose. The two are siblings in one vocabulary and
/// the thing worth checking is that they read as the same KIND of chip while staying
/// distinguishable: same height, same radius, same icon size, different tone. If the
/// low-stock chip looks heavier than the expiring one, the severity ordering that
/// `expiryBadgeRecipe` documents is broken.
///
/// The second group is the [StockBadge.maybe] contract, which is the part that can
/// silently regress: only the middle case may render anything.
class StockBadgePreview extends StatelessWidget {
  /// Creates the StockBadge preview.
  const StockBadgePreview({super.key});

  @override
  Widget build(BuildContext context) {
    return WDiv(
      className: 'flex flex-col gap-6 p-6',
      children: [
        WDiv(
          className: 'flex flex-col gap-2',
          children: [
            WText('Bir sözlük: aynı yükseklik, farklı ton', className: 'text-xs text-fg-muted'),
            WDiv(
              className: 'flex flex-row items-center gap-2',
              children: [
                const StockBadge(),
                const ExpiryBadge(label: '2 gün', daysUntilExpiry: 2),
                const ExpiryBadge(label: 'Süresi geçti', daysUntilExpiry: -1),
                const ExpiryBadge(label: '38 gün', daysUntilExpiry: 38),
              ],
            ),
          ],
        ),
        WDiv(
          className: 'flex flex-col gap-2',
          children: [
            WText('maybe(): sadece ortadaki bir şey çizmeli', className: 'text-xs text-fg-muted'),
            WDiv(
              className: 'flex flex-row items-center gap-2',
              children: [
                WText('hedef yok:', className: 'text-xs text-fg-disabled'),
                ?StockBadge.maybe(amount: 3, parLevel: null),
                WText('3 / 10:', className: 'text-xs text-fg-disabled'),
                ?StockBadge.maybe(amount: 3, parLevel: 10),
                WText('sıfır:', className: 'text-xs text-fg-disabled'),
                ?StockBadge.maybe(amount: 0, parLevel: 10),
                WText('hedefin üstünde:', className: 'text-xs text-fg-disabled'),
                ?StockBadge.maybe(amount: 12, parLevel: 10),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
