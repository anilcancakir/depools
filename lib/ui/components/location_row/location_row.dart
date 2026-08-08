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

  /// The location's icon. Required, because every node in the tree has one: a tree where
  /// only roots carry a glyph makes children read as text under a heading rather than as
  /// places, and `locations.icon_id` exists for every row.
  final IconData icon;

  /// Called when the row is tapped, which opens the location.
  final VoidCallback? onTap;

  /// Creates a [LocationRow].
  const LocationRow({
    super.key,
    required this.name,
    required this.depth,
    required this.productCount,
    required this.icon,
    this.itemSummary,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final slots = locationRowRecipe()(variants: {'state': productCount == 0 ? 'empty' : 'stocked'});

    return WAnchor(
      onTap: onTap,
      semanticLabel: Lang.get('components.location_row.label', {
        'name': name,
        'summary': itemSummary ?? Lang.get('components.location_row.empty'),
      }),
      child: WDiv(
        // The indent is padding on the row rather than a spacer child, so the whole row
        // stays one tap target at every depth. A nested Row of spacers would put the
        // 44pt floor on the label instead of on the thing the user aims at.
        className: '${slots['root']} ${_indentFor(depth)}',
        children: [
          // The icon is REQUIRED rather than reserved-when-absent, which is the stronger
          // version of the same fix. A conditional leading glyph shifted the text beside
          // it, so a root with an icon pushed its name 32px right while its child got 12px
          // of indent and children appeared to the LEFT of their parents. Making it
          // required removes the state that caused it instead of padding around it.
          WIcon(icon, className: slots['icon']),
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
