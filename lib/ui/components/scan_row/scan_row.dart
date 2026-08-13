import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../../app/models/scan_source.dart';

// Re-exported so a widget that already reached `ScanSource` through this component keeps working.
// The enum itself lives in the app layer, because a model naming it must not import a widget.
export '../../../app/models/scan_source.dart';

import '../quantity/quantity.dart';
import 'scan_row.recipe.dart';


/// **ScanRow**
///
/// One barcode in a continuous scan batch: what was read, what it resolved to, how far to
/// trust it, and how many times it was scanned.
///
/// **The barcode is always shown, even after a confident match.** Same reason
/// `ReceiptLineRow` always shows the extracted string: resolution is a claim about a
/// machine reading, and the only thing the user can check it against is the label in
/// their hand. It renders in mono so it can be compared digit by digit.
///
/// **Provenance appears only when the answer is not the tenant's own inventory.** That
/// closes `barcode-and-catalog.md`'s own open question, which asked how to show
/// provenance "without cluttering the UI ... should not have to read a source label on
/// every row". Silence means authoritative. It is the same logic as `DraftField`'s
/// unconfirmed mark: the annotation goes where trust is lower, not everywhere.
///
/// **The count is scans, not stock.** A repeat scan of the same barcode increments this
/// row rather than appending another (D40), so six identical yoghurts are one row reading
/// six. The existing stock, when there is any, is stated separately and labelled, because
/// two bare numbers in the same unit on one row is how a user ends up reading the wrong
/// one.
@immutable
class ScanRow extends StatelessWidget {
  static const IconData _ownIcon = Icons.check_circle_outline;
  static const IconData _catalogIcon = Icons.add_circle_outline;
  static const IconData _recalledIcon = Icons.history;
  static const IconData _unmatchedIcon = Icons.help_outline;

  /// The digits as the scanner read them.
  final String barcode;

  /// The product the barcode resolved to. Null while [source] is unmatched.
  final String? productName;

  /// Which stage answered.
  final ScanSource source;

  /// How many times this barcode was scanned in this batch.
  final int count;

  /// The unit the count is in.
  final String unit;

  /// The already-formatted stock the tenant already holds, when [source] is own. `'0'` is
  /// a real value and worth showing: the product is known and there is none left, which
  /// is exactly when a scan is most useful.
  final String? onHandFormatted;

  /// Called when the row is tapped to correct or resolve it.
  final VoidCallback? onTap;

  /// Creates a [ScanRow].
  const ScanRow({
    super.key,
    required this.barcode,
    required this.count,
    this.productName,
    this.source = ScanSource.own,
    this.unit = 'adet',
    this.onHandFormatted,
    this.onTap,
  });

  /// The recipe variant. Four of the five states will be written as they stand, so they
  /// collapse into two looks; only [ScanSource.unmatched] asks for anything.
  String get _stateKey => switch (source) {
    ScanSource.unmatched => 'attention',
    ScanSource.unverified => 'unverified',
    ScanSource.own || ScanSource.catalog || ScanSource.recalled => 'settled',
  };

  /// The leading glyph. **Every state has one**, and the column is a fixed-size box
  /// whether or not the glyph inside it varies, because a conditional glyph shifts the
  /// text beside it and ragged text destroys the alignment the row was carrying.
  ///
  /// `catalog` and `unverified` share a glyph on purpose: the icon says what will HAPPEN
  /// (a product gets created), and how much to trust it is the meta line's job. Tone
  /// separates them too, but tone is never the only carrier.
  IconData get _icon => switch (source) {
    ScanSource.own => _ownIcon,
    ScanSource.catalog || ScanSource.unverified => _catalogIcon,
    ScanSource.recalled => _recalledIcon,
    ScanSource.unmatched => _unmatchedIcon,
  };

  /// The already-localised meta line: what this row will do, and how far to trust it.
  String? get _meta => switch (source) {
    // Labelled, because the trailing figure on this same row is a scan count in the same
    // unit. "Mevcut: 2 adet" states which number is which; "2 adet" would not.
    ScanSource.own => onHandFormatted == null ? null : Lang.get('components.scan_row.on_hand', {'amount': onHandFormatted, 'unit': unit}),
    ScanSource.catalog => Lang.get('components.scan_row.new_catalog'),
    ScanSource.unverified => Lang.get('components.scan_row.new_unverified'),
    ScanSource.recalled => Lang.get('components.scan_row.new_manual'),
    ScanSource.unmatched => null,
  };

  @override
  Widget build(BuildContext context) {
    final slots = scanRowRecipe()(variants: {'state': _stateKey});
    final bool isUnmatched = source == ScanSource.unmatched;

    return WAnchor(
      onTap: onTap,
      semanticLabel: isUnmatched
          ? Lang.get('components.scan_row.unmatched_label', {'barcode': barcode})
          : [productName ?? barcode, '$count $unit', ?_meta].join(', '),
      child: WDiv(
        className: slots['root'],
        children: [
          WDiv(
            className: slots['iconBox'],
            child: WIcon(_icon, className: slots['icon']),
          ),
          WDiv(
            className: slots['body'],
            children: [
              // The hierarchy inverts for an unmatched scan, the same way it does in
              // `ReceiptLineRow`: when the barcode is all that is known, the barcode is
              // the content and it leads. For a resolved scan the name leads and the
              // barcode becomes the evidence underneath it.
              if (isUnmatched) ...[
                WText(barcode, className: slots['unmatchedBarcode']),
                WText(Lang.get('components.scan_row.unmatched'), className: slots['prompt']),
              ] else ...[
                WText(productName ?? barcode, className: slots['name']),
                WText(barcode, className: slots['barcode']),
              ],
              if (_meta != null) WText(_meta!, className: slots['meta']),
            ],
          ),
          WDiv(
            className: slots['trailing'],
            child: Quantity(amount: count, formatted: '$count', unit: unit, size: QuantitySize.sm),
          ),
        ],
      ),
    );
  }
}
