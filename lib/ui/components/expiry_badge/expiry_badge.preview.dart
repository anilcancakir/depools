import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import 'expiry_badge.dart';

/// Static variant-matrix preview for [ExpiryBadge].
///
/// The second row is the case worth checking: three lots of the same product with
/// different dates, which is what a product detail screen actually has to show and
/// what a single expiry field on the product could never express.
class ExpiryBadgePreview extends StatelessWidget {
  /// Creates the ExpiryBadge preview.
  const ExpiryBadgePreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const WDiv(
      className: 'flex flex-col gap-6 p-6',
      children: [
        WDiv(
          className: 'flex flex-row wrap items-center gap-2',
          children: [
            ExpiryBadge(label: '4 gün önce geçti', daysUntilExpiry: -4),
            ExpiryBadge(label: 'Bugün', daysUntilExpiry: 0),
            ExpiryBadge(label: '2 gün', daysUntilExpiry: 2),
            ExpiryBadge(label: '12 Eyl', daysUntilExpiry: 38),
          ],
        ),
        WDiv(
          className: 'flex flex-col gap-2 p-3 rounded-md bg-surface-container-high',
          children: [
            WText('Pınar Süt Tam Yağlı 1 lt', className: 'text-sm font-semibold text-fg'),
            WDiv(
              className: 'flex flex-row wrap items-center gap-2',
              children: [
                ExpiryBadge(label: 'Süresi geçti', daysUntilExpiry: -1),
                ExpiryBadge(label: '2 gün', daysUntilExpiry: 2),
                ExpiryBadge(label: '9 gün', daysUntilExpiry: 9),
              ],
            ),
          ],
        ),
        WText(
          'Tarihi olmayan parti hiç rozet göstermez: ExpiryBadge.maybe null döner, '
          'böylece ebeveynin gap ayırıcısı da oluşmaz.',
          className: 'text-xs text-fg-muted',
        ),
      ],
    );
  }
}
