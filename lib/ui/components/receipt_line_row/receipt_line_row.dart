import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../quantity/quantity.dart';
import 'receipt_line_row.recipe.dart';

/// How far a receipt line got, per `receipt_lines.resolution_state`.
enum LineResolution {
  /// The abbreviated name could not be turned into a product. Needs the user.
  unresolved,

  /// Resolved to a product the tenant already had.
  matched,

  /// Resolved by creating a new product from the line.
  created,

  /// The user dropped this line. Kept visible so the receipt still reconciles.
  rejected,
}

/// **ReceiptLineRow**
///
/// One line off a receipt: what the paper said, what it became, how much, and what it
/// cost.
///
/// **The extracted string is always shown, even after resolution.** Turkish thermal
/// receipts truncate ("PNR SUT 1LT" for a litre of Pınar milk), and resolution is a
/// guess about an abbreviation. Hiding the original would leave the user unable to check
/// the one thing they can check: the paper in their hand. It renders in mono, because it
/// is a machine's reading being compared character by character.
///
/// **The default is accepted, and only exceptions ask for anything.** That is not a
/// shortcut, it is what `receipt-ingestion.md`'s own acceptance criterion requires: a 15
/// to 25 line receipt should be accepted "with edits to fewer than 3 lines", which means
/// nineteen lines pass untouched. A screen demanding twenty-two explicit taps would
/// satisfy "mandatory per-line confirmation" literally and fail the criterion that
/// matters.
///
/// So `matched` and `created` look alike here: both are settled, and the difference
/// belongs in the meta line rather than in the row's weight.
@immutable
class ReceiptLineRow extends StatelessWidget {
  static const IconData _matchedIcon = Icons.check_circle_outline;
  static const IconData _unresolvedIcon = Icons.help_outline;
  static const IconData _createdIcon = Icons.add_circle_outline;
  static const IconData _rejectedIcon = Icons.remove_circle_outline;

  /// What the extraction read off the paper, verbatim.
  final String extracted;

  /// The product this line became. Null while [resolution] is unresolved.
  final String? productName;

  /// How far this line got.
  final LineResolution resolution;

  /// The raw quantity, used to derive the zero treatment.
  final num amount;

  /// The already-formatted quantity.
  final String formatted;

  /// The unit.
  final String? unit;

  /// The already-formatted line total, for example `'34,90 TL'`.
  final String? price;

  /// The already-formatted location this line will go to.
  final String? locationLabel;

  /// Called when the row is tapped to resolve or change it.
  final VoidCallback? onTap;

  /// Creates a [ReceiptLineRow].
  const ReceiptLineRow({
    super.key,
    required this.extracted,
    required this.amount,
    required this.formatted,
    this.productName,
    this.resolution = LineResolution.matched,
    this.unit,
    this.price,
    this.locationLabel,
    this.onTap,
  });

  /// The recipe variant, collapsing the two settled states into one look.
  String get _stateKey => switch (resolution) {
    LineResolution.unresolved => 'unresolved',
    LineResolution.rejected => 'rejected',
    LineResolution.matched || LineResolution.created => 'settled',
  };

  /// The leading glyph. **Every state has one.**
  ///
  /// A first pass gave the matched state no icon, reasoning that the absence of a mark
  /// is the clearest "nothing to do here". It is not: it left the column half empty and
  /// the left edge ragged, and it read as unfinished rather than as deliberate.
  ///
  /// The hierarchy is carried by TONE instead, which is the better tool for it: icons
  /// are visually heavy, so the settled ones sit in `text-fg-disabled` and recede while
  /// the unresolved one takes the accent. Consistent column, state in the glyph and the
  /// weight, and colour is never the only carrier.
  IconData get _icon => switch (resolution) {
    LineResolution.unresolved => _unresolvedIcon,
    LineResolution.created => _createdIcon,
    LineResolution.rejected => _rejectedIcon,
    LineResolution.matched => _matchedIcon,
  };

  /// The glyph's tone, which is what separates "needs you" from "done".
  String get _iconTone => switch (resolution) {
    LineResolution.unresolved => 'size-4 text-ai',
    LineResolution.created => 'size-4 text-fg-muted',
    LineResolution.matched || LineResolution.rejected => 'size-4 text-fg-disabled',
  };

  /// The already-localised meta line: where it goes, and how it resolved when that is
  /// worth saying.
  String? get _meta {
    final List<String> parts = <String>[
      if (resolution == LineResolution.created) Lang.get('components.receipt_line_row.new_product'),
      if (resolution == LineResolution.rejected) Lang.get('components.receipt_line_row.skipped'),
      ?locationLabel,
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final slots = receiptLineRowRecipe()(variants: {'state': _stateKey});

    return WAnchor(
      onTap: onTap,
      semanticLabel: switch (resolution) {
        LineResolution.unresolved => Lang.get('components.receipt_line_row.unmatched_label', {'text': extracted}),
        LineResolution.rejected => Lang.get('components.receipt_line_row.skipped_label', {'text': extracted}),
        _ => Lang.get('components.receipt_line_row.label', {
          'name': productName ?? extracted,
          'amount': formatted,
          'unit': unit ?? '',
        }),
      },
      child: WDiv(
        className: slots['root'],
        children: [
          WDiv(
            className: 'size-4 shrink-0 flex items-center justify-center',
            child: WIcon(_icon, className: _iconTone),
          ),
          WDiv(
            className: slots['body'],
            children: [
              // **The hierarchy inverts for an unresolved line, and it has to.** A first
              // pass made "Eşleştirilemedi" the primary text, which stacked four
              // identical headlines down the card: the row's most prominent line carried
              // no information and the only thing distinguishing the four sat beneath it
              // in muted mono.
              //
              // For an unresolved line the extracted string IS the content, because it is
              // all that is known, so it leads. The state moves underneath. For a
              // resolved line the product name leads and the extracted string is the
              // evidence, which is the other way round for the same reason.
              if (resolution == LineResolution.unresolved) ...[
                WText(extracted, className: slots['unresolvedName']),
                WText(Lang.get('components.receipt_line_row.unmatched'), className: slots['prompt']),
              ] else ...[
                WText(productName ?? extracted, className: slots['name']),
                // The paper's own words, always. This is what the user checks against.
                WText(extracted, className: slots['extracted']),
              ],
              if (_meta != null) WText(_meta!, className: slots['meta']),
            ],
          ),
          WDiv(
            className: slots['trailing'],
            children: [
              Quantity(
                amount: resolution == LineResolution.rejected ? 0 : amount,
                formatted: formatted,
                unit: unit,
                size: QuantitySize.sm,
              ),
              // The price comes free off the receipt and it is what values waste later,
              // so dropping it here would mean asking for it again.
              if (price != null) WText(price!, className: slots['meta']),
            ],
          ),
        ],
      ),
    );
  }
}
