import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart' show MSSkeleton, SkeletonShape;

import '../expiry_badge/expiry_badge.dart';
import '../product_thumb/product_thumb.dart';
import '../quantity/quantity.dart';
import '../stock_badge/stock_badge.dart';
import 'product_row.recipe.dart';

/// **ProductRow**
///
/// One product in a list: what it is, roughly where it lives, how much there is in
/// total, and whether anything about it needs attention.
///
/// Distinct from `LocationStockRow` on purpose. That row answers "how much of this
/// product is at this location" and repeats per location inside a product's detail;
/// this one answers "what is this and how much is there altogether" and repeats per
/// product in a list. Merging them would mean one component with two meanings for its
/// quantity, which is how a list starts showing per-location numbers as if they were
/// totals.
///
/// [locationSummary] is already-joined text like "Buzdolabı, Kiler" or "2 konumda",
/// because how many locations to name before collapsing to a count is a presentation
/// decision, and pushing a list into every row would make the caller build the same
/// string anyway.
///
/// ### Example
///
/// ```dart
/// ProductRow(
///   name: 'Pınar Süt Tam Yağlı 1 lt',
///   meta: 'Pınar · Buzdolabı, Kiler',
///   amount: 5, formatted: '5', unit: 'adet',
///   expiryLabel: 'Süresi geçti', daysUntilExpiry: -1,
/// )
/// ```
@immutable
class ProductRow extends StatelessWidget {
  /// The product name, already localised. Truncates rather than wrapping.
  final String name;

  /// The primary picture's url, when the product has one.
  ///
  /// Null is the ordinary case rather than the exception: nothing writes a product's image until the
  /// tenant uploads one, so most rows fall back to the name's initial. That is why the box is drawn by
  /// [ProductThumb], which reserves the same geometry either way.
  final String? imageUrl;

  /// The already-joined brand and location line.
  final String? meta;

  /// The raw total across every location, used to derive the zero treatment.
  final num amount;

  /// The already-formatted total for the active locale.
  final String formatted;

  /// The product's base unit.
  final String? unit;

  /// An already-formatted remainder for an open unit, rendered after a `+`.
  final String? remainderFormatted;

  /// The remainder's unit.
  final String? remainderUnit;

  /// The already-formatted earliest expiry across every lot.
  final String? expiryLabel;

  /// Days until that earliest expiry.
  final int? daysUntilExpiry;

  /// The user-set target level, used to decide whether to show a low-stock badge.
  ///
  /// Without this the row cannot say WHY a product with stock on hand needs
  /// attention. "3 adet" is not low on its own; it is low against a target of ten,
  /// and a warning that does not name its own cause gets ignored or distrusted.
  final num? parLevel;

  /// Called when the row is tapped, which opens the product.
  final VoidCallback? onTap;

  /// Whether this is a placeholder for a row still loading.
  ///
  /// **The skeleton is the row's own shadow, not three grey bars.** A generic bar list says
  /// "something is coming"; a placeholder with the row's real geometry says WHAT is coming, and
  /// it stops the list jumping when the content lands. The only way to guarantee the two match
  /// is for the same component to draw both, which is why this is a constructor here rather
  /// than a separate widget that would drift the first time the row changed.
  final bool isSkeleton;

  /// Creates a [ProductRow].
  const ProductRow({
    super.key,
    required this.name,
    required this.amount,
    required this.formatted,
    this.imageUrl,
    this.meta,
    this.unit,
    this.remainderFormatted,
    this.remainderUnit,
    this.expiryLabel,
    this.daysUntilExpiry,
    this.parLevel,
    this.onTap,
  }) : isSkeleton = false;

  /// Creates a placeholder with this row's exact geometry.
  ///
  /// Every measurement comes from the same recipe the real row uses, so the thumb, the two text
  /// lines and the trailing figure land where the content will.
  const ProductRow.skeleton({super.key})
    : name = '',
      imageUrl = null,
      meta = null,
      amount = 0,
      formatted = '',
      unit = null,
      remainderFormatted = null,
      remainderUnit = null,
      expiryLabel = null,
      daysUntilExpiry = null,
      parLevel = null,
      onTap = null,
      isSkeleton = true;

  @override
  Widget build(BuildContext context) {
    final slots = productRowRecipe()(variants: {'state': amount == 0 ? 'depleted' : 'stocked'});

    if (isSkeleton) return _buildSkeleton(slots);

    return WAnchor(
      onTap: onTap,
      child: WDiv(
        className: slots['root'],
        children: [
          // The component rather than the slot: it draws the same box, and it fills it with the
          // picture when there is one and the product's initial when there is not. A generic photo
          // glyph on every row was the same mark repeated down the list, which told the reader
          // nothing and made two adjacent rows harder to tell apart rather than easier.
          ProductThumb(name: name, imageUrl: imageUrl),
          WDiv(
            className: slots['body'],
            children: [
              WText(name, className: slots['name']),
              if (meta != null) WText(meta!, className: slots['meta']),
            ],
          ),
          WDiv(
            className: slots['trailing'],
            children: [
              Quantity(
                amount: amount,
                formatted: formatted,
                unit: unit,
                remainderFormatted: remainderFormatted,
                remainderUnit: remainderUnit,
              ),
              // ONE badge, the most urgent. A product can be both expired and below
              // par, and rendering both stacked them into a three-line row: the
              // attention list lost its uniform rhythm and the date, which is the
              // signal with a deadline, stopped leading. Whichever is worse is what
              // the user acts on first, and acting on it changes the other anyway
              // (throwing out the expired carton makes the shortfall bigger).
              //
              // The full picture belongs on the detail screen, which has the room to
              // show the target level and every lot date at once.
              ?_buildBadge(),
            ],
          ),
        ],
      ),
    );
  }

  /// The single most urgent status, or null when nothing needs saying.
  ///
  /// Order: expired, then expiring, then below par. Expiry outranks stock level
  /// because it has a deadline that no amount of reordering fixes.
  Widget? _buildBadge() {
    final Widget? expiry = ExpiryBadge.maybe(label: expiryLabel, daysUntilExpiry: daysUntilExpiry);
    if (expiry != null) return expiry;
    return StockBadge.maybe(amount: amount, parLevel: parLevel);
  }

  /// The same three columns, filled with skeletons instead of content.
  ///
  /// The two text lines are different widths because a name and a meta line are: equal bars
  /// read as a table of empty cells rather than as a row about to have a product in it.
  Widget _buildSkeleton(Map<String, String> slots) {
    return WDiv(
      className: slots['root'],
      children: [
        // The thumb slot already carries its own fill and radius, so the placeholder is the
        // slot itself with nothing in it.
        WDiv(className: slots['thumb']),
        WDiv(
          className: slots['body'],
          children: const [
            MSSkeleton(shape: SkeletonShape.text, width: 160, height: 14),
            MSSkeleton(shape: SkeletonShape.text, width: 104, height: 12),
          ],
        ),
        const WDiv(
          className: 'flex flex-col items-end gap-1',
          child: MSSkeleton(shape: SkeletonShape.text, width: 48, height: 14),
        ),
      ],
    );
  }
}
