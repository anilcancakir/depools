import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import 'filter_chip.dart';

/// Static variant-matrix preview for [FilterChip].
///
/// The two states one above the other, which is the only thing worth checking: an
/// idle chip and an applied chip have to be distinguishable at a glance in both
/// appearances. If they read alike, the user cannot tell what is filtering the list
/// from what is merely on offer, and that is the failure this component exists to
/// avoid.
///
/// The third group is the long-label case. These live in a horizontally scrolling
/// row, so a long chip should scroll off rather than wrap or squeeze its neighbours.
class FilterChipPreview extends StatelessWidget {
  /// A tear-off rather than a closure, so every `const` in this file survives.
  ///
  /// The callbacks are here at all because a control previewed WITHOUT one is a dead
  /// control: `WAnchor` withholds the pointer cursor when it has no gesture, so the
  /// catalog showed no hand on hover and it was reported as a missing cursor in code
  /// that works. Eleven previews had this.
  static void _noop() {}

  /// Creates the FilterChip preview.
  const FilterChipPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const WDiv(
      className: 'flex flex-col gap-6 p-6',
      children: [
        WDiv(
          className: 'flex flex-col gap-2',
          children: [
            WText('Idle: bir teklif', className: 'text-xs text-fg-muted'),
            WDiv(
              className: 'flex flex-row items-center gap-2 w-full overflow-x-auto',
              children: [
                FilterChip(label: 'Süresi geçenler', onTap: _noop),
                FilterChip(label: 'Yakında bitecek', onTap: _noop),
                FilterChip(label: 'Stok yok', onTap: _noop),
              ],
            ),
          ],
        ),
        WDiv(
          className: 'flex flex-col gap-2',
          children: [
            WText('Applied: şu anda listeyi daraltıyor', className: 'text-xs text-fg-muted'),
            WDiv(
              className: 'flex flex-row items-center gap-2 w-full overflow-x-auto',
              children: [
                FilterChip(label: 'Süresi geçti', applied: true, onTap: _noop),
                FilterChip(label: 'Kiler', applied: true, onTap: _noop),
                FilterChip(label: '"süt"', applied: true, onTap: _noop),
              ],
            ),
          ],
        ),
        WDiv(
          className: 'flex flex-col gap-2',
          children: [
            WText('Uzun etiket', className: 'text-xs text-fg-muted'),
            WDiv(
              className: 'flex flex-row items-center gap-2 w-full overflow-x-auto',
              children: [
                FilterChip(label: 'Depo › Koridor B › Raf 14 › Kutu 3', applied: true, onTap: _noop),
                FilterChip(label: 'Bakliyat ve tahıl ürünleri', onTap: _noop),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
