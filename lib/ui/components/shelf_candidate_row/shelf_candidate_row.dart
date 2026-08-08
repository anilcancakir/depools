import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../quantity/quantity.dart';
import '../receipt_line_row/receipt_line_row.dart' show LineResolution;
import 'shelf_candidate_row.recipe.dart';

/// **ShelfCandidateRow**
///
/// One thing the app thinks it can see in a shelf photograph.
///
/// **It shares `LineResolution` with the receipt review rather than defining a fourth enum.**
/// The concept is identical: an extracted thing resolving to a product, or failing to. What
/// differs is the EVIDENCE a user checks it against, which is a printed string on a receipt
/// and a numbered region on a photograph, so the row is separate and the vocabulary is not.
/// (`ScanRow` is the opposite case: same-looking row, genuinely different concept, so it has
/// its own enum.)
///
/// **The region number is not decoration** (D60). It is the only thing tying a row to a box on
/// the picture above it, so it renders on every row, in mono, at a fixed width. Order cannot do
/// that job: rows get filtered and reordered, boxes stay where the shelf put them.
@immutable
class ShelfCandidateRow extends StatelessWidget {
  /// The region's number, matching the box drawn on the photograph.
  final int region;

  /// What the app recognised. Null while [resolution] is unresolved.
  final String? productName;

  /// How far this candidate got.
  final LineResolution resolution;

  /// The raw quantity, for the zero treatment.
  final num amount;

  /// The already-formatted quantity.
  final String formatted;

  /// The unit.
  final String unit;

  /// The already-localised meta line: what will happen, and anything worth knowing.
  final String? meta;

  /// Called when the row is tapped to review or correct it.
  final VoidCallback? onTap;

  /// Creates a [ShelfCandidateRow].
  const ShelfCandidateRow({
    super.key,
    required this.region,
    required this.amount,
    required this.formatted,
    this.productName,
    this.resolution = LineResolution.matched,
    this.unit = 'adet',
    this.meta,
    this.onTap,
  });

  String get _stateKey => switch (resolution) {
    LineResolution.unresolved => 'unresolved',
    LineResolution.rejected => 'rejected',
    LineResolution.matched || LineResolution.created => 'settled',
  };

  @override
  Widget build(BuildContext context) {
    final slots = shelfCandidateRowRecipe()(variants: {'state': _stateKey});
    final bool isUnresolved = resolution == LineResolution.unresolved;

    return WAnchor(
      onTap: onTap,
      semanticLabel: isUnresolved
          ? Lang.get('components.shelf_candidate_row.unrecognised_label', {'region': region})
          : '$region numaralı bölge, ${productName ?? ''}, $formatted $unit',
      child: WDiv(
        className: slots['root'],
        children: [
          WDiv(
            className: slots['badge'],
            child: WText('$region', className: slots['badgeText']),
          ),
          WDiv(
            className: slots['body'],
            children: [
              // An unresolved candidate has no name to lead with, so the prompt takes the
              // primary line. Same inversion `ReceiptLineRow` makes, for the same reason:
              // the row's most prominent line has to carry information.
              if (isUnresolved)
                WText(Lang.get('components.shelf_candidate_row.unrecognised'), className: slots['prompt'])
              else
                WText(productName ?? '', className: slots['name']),
              if (meta != null) WText(meta!, className: slots['meta']),
            ],
          ),
          WDiv(
            className: slots['trailing'],
            child: Quantity(
              amount: resolution == LineResolution.rejected ? 0 : amount,
              formatted: formatted,
              unit: unit,
              size: QuantitySize.sm,
            ),
          ),
        ],
      ),
    );
  }
}
