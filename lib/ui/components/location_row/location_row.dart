import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import 'location_row.recipe.dart';

/// **LocationRow**
///
/// One node in the location tree: its own name, what it holds, and how deep it sits.
///
/// **It shows its own name, never the full path.** The ancestors are on screen directly
/// above it, so repeating "Mutfak › Buzdolabı" in a tree is the redundancy that makes a
/// hierarchy unreadable. `LocationStockRow` on the product screen does the opposite for
/// the opposite reason: there the tree is absent, so the path is the only context.
///
/// **The count includes descendants.** A user reading "Mutfak, 5 ürün" means everything
/// in the kitchen, not the items sitting loose in the room and not in one of its
/// cupboards. When a parent holds nothing directly, the count is still its subtree's, and
/// the meta line says how that breaks down so the number is never a mystery.
///
/// ### Example
///
/// ```dart
/// LocationRow(name: 'Buzdolabı', depth: 1, productCount: 3, itemSummary: '3 ürün')
/// ```
@immutable
class LocationRow extends StatelessWidget {
  /// The location's own name, as the user typed it.
  final String name;

  /// How deep this node sits. 0 is a root.
  final int depth;

  /// How many products the subtree holds, used to derive the empty treatment.
  final int productCount;

  /// The already-formatted contents line, for example `'3 ürün · 2 parti'`.
  final String? itemSummary;

  /// An optional leading icon, from the location's own icon choice.
  final IconData? icon;

  /// Called when the row is tapped, which opens the location.
  final VoidCallback? onTap;

  /// Creates a [LocationRow].
  const LocationRow({
    super.key,
    required this.name,
    required this.depth,
    required this.productCount,
    this.itemSummary,
    this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final slots = locationRowRecipe()(variants: {'state': productCount == 0 ? 'empty' : 'stocked'});

    return WAnchor(
      onTap: onTap,
      semanticLabel: '$name, ${itemSummary ?? 'boş'}',
      child: WDiv(
        // The indent is padding on the row rather than a spacer child, so the whole row
        // stays one tap target at every depth. A nested Row of spacers would put the
        // 44pt floor on the label instead of on the thing the user aims at.
        className: '${slots['root']} ${_indentFor(depth)}',
        children: [
          // **The icon gutter is always reserved, even when there is no icon.** Rendering
          // it conditionally inverted the tree: a root with an icon had its name pushed
          // 32px right by the glyph and gap, while its depth-1 child got only 12px of
          // indent, so the child appeared to the LEFT of its parent and the nesting read
          // backwards.
          //
          // Second time this exact mistake in one session, after fixing it in
          // ReceiptLineRow. The rule was written for "some states have an icon" and this
          // is "some rows have an icon", so it did not obviously apply. It does: any
          // conditional leading glyph shifts the text beside it, and text that shifts
          // per-row destroys whatever alignment the layout was carrying.
          WDiv(
            className: 'size-5 shrink-0 flex items-center justify-center',
            child: icon == null ? null : WIcon(icon!, className: slots['icon']),
          ),
          WDiv(
            className: slots['body'],
            children: [
              WText(name, className: slots['name']),
              if (itemSummary != null) WText(itemSummary!, className: slots['meta']),
            ],
          ),
        ],
      ),
    );
  }

  /// The left padding for a depth, capped at the schema's maximum of 6 levels.
  ///
  /// Written as a switch over literal tokens rather than an interpolated `pl-${depth*3}`
  /// because Wind parses className at build time and caches on the literal string: an
  /// interpolated class defeats the cache and, worse, a value the parser does not know
  /// drops silently.
  static String _indentFor(int depth) => switch (depth.clamp(0, 5)) {
    0 => '',
    1 => 'pl-3',
    2 => 'pl-6',
    3 => 'pl-9',
    4 => 'pl-12',
    _ => 'pl-14',
  };
}
