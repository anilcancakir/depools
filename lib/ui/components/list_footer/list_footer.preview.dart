import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import 'list_footer.dart';

/// Static variant-matrix preview for [ListFooter].
///
/// The three endings side by side. The check is that none of them could be mistaken for
/// another: a list that stopped because it finished, one that is still fetching, and one
/// that broke are three different situations, and a user who cannot tell them apart stops
/// scrolling at the wrong moment or distrusts rows that are fine.
class ListFooterPreview extends StatelessWidget {
  /// Creates the ListFooter preview.
  const ListFooterPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const WDiv(
      className: 'flex flex-col gap-6 p-6',
      children: [
        WDiv(
          className: 'flex flex-col gap-2 p-4 rounded-lg bg-surface-container',
          children: [
            WText('Sayfa geliyor', className: 'text-xs text-fg-muted'),
            ListFooter(state: ListFooterState.loadingMore),
          ],
        ),
        WDiv(
          className: 'flex flex-col gap-2 p-4 rounded-lg bg-surface-container',
          children: [
            WText('Liste bitti', className: 'text-xs text-fg-muted'),
            ListFooter(state: ListFooterState.end, totalLabel: '1.240 ürünün hepsi yüklendi'),
          ],
        ),
        WDiv(
          className: 'flex flex-col gap-2 p-4 rounded-lg bg-surface-container',
          children: [
            WText('Sayfa hata verdi', className: 'text-xs text-fg-muted'),
            ListFooter(state: ListFooterState.error),
          ],
        ),
      ],
    );
  }
}
