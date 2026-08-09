import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../receipt_line_row/receipt_line_row.dart' show LineResolution;
import 'shelf_candidate_row.dart';

/// Static variant-matrix preview for [ShelfCandidateRow].
///
/// All four states a candidate can be in, in the order the numbers run. The one to read is the
/// last: the recogniser took a shelf label for a product, and rejecting it is routine rather
/// than an edge case, so the row has to stay visible or a mis-tap could not be undone.
///
/// Two things to check. The region badges must line up down the left edge, because the number is
/// the ONLY thing tying a row to a box on the photograph and a ragged column breaks the one job
/// it has. And the unresolved row must lead with its prompt rather than an empty name, since a
/// blank primary line carries nothing.
class ShelfCandidateRowPreview extends StatelessWidget {
  /// A tear-off rather than a closure, so every `const` in this file survives.
  ///
  /// The callbacks are here at all because a control previewed WITHOUT one is a dead
  /// control: `WAnchor` withholds the pointer cursor when it has no gesture, so the
  /// catalog showed no hand on hover and it was reported as a missing cursor in code
  /// that works. Eleven previews had this.
  static void _noop() {}

  /// Creates the ShelfCandidateRow preview.
  const ShelfCandidateRowPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const WDiv(
      className: 'flex flex-col gap-6 p-6',
      children: [
        WDiv(
          className: 'flex flex-col gap-1 p-4 rounded-lg bg-surface-container',
          children: [
            ShelfCandidateRow(
              region: 1,
              productName: 'Pınar Süt Tam Yağlı 1 lt',
              amount: 2,
              formatted: '2',
              meta: 'Envanterinizde',
            onTap: _noop),
            ShelfCandidateRow(
              region: 2,
              productName: 'Sütaş Ayran 250 ml',
              resolution: LineResolution.created,
              amount: 4,
              formatted: '4',
              meta: 'Yeni ürün · katalogdan',
            onTap: _noop),
            ShelfCandidateRow(
              region: 3,
              resolution: LineResolution.unresolved,
              amount: 1,
              formatted: '1',
            onTap: _noop),
            ShelfCandidateRow(
              region: 4,
              productName: 'Fiyat etiketi',
              resolution: LineResolution.rejected,
              amount: 1,
              formatted: '1',
              meta: 'Atlandı · ürün değil',
            onTap: _noop),
          ],
        ),
      ],
    );
  }
}
