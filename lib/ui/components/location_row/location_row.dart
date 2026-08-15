import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../../app/support/location_appearance.dart';
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
/// LocationRow(
///   name: 'Buzdolabı',
///   depth: 1,
///   productCount: 3,
///   itemSummary: '3 ürün',
///   icon: 'fridge',
///   colour: 'blue',
/// )
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

  /// The location's icon NAME, from the closed catalogue in `location_appearance.dart`.
  ///
  /// A name rather than an `IconData` because that is what the column holds, and because a
  /// glyph built from a stored codepoint is shaken out of the font by the release build.
  /// Null falls back to a neutral box: both columns are nullable, and the leading glyph is
  /// unconditional, since a tree where only some rows carry one shifts the text beside it.
  final String? icon;

  /// The location's hue NAME, from the same catalogue.
  ///
  /// **The tint identifies a place, it does not assert a state.** Several hues share a hex
  /// with a status family because both come from Apple's increased-contrast palette, and
  /// that is safe for the reason DESIGN.md already relies on: a status in this app always
  /// arrives as a filled badge carrying an icon AND its word, so a bare tint cannot be read
  /// as one. Null falls back to the neutral.
  final String? colour;

  /// Called when the row is tapped, which opens the location.
  final VoidCallback? onTap;

  /// Creates a [LocationRow].
  const LocationRow({
    super.key,
    required this.name,
    required this.depth,
    required this.productCount,
    this.icon,
    this.colour,
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
          // The glyph is UNCONDITIONAL rather than reserved-when-absent, which is the
          // stronger version of the same fix. A conditional leading glyph shifted the text
          // beside it, so a root with an icon pushed its name 32px right while its child got
          // 12px of indent and children appeared to the LEFT of their parents. Both columns
          // are nullable on the backend, so the fallback lives in the resolver rather than
          // in a condition here: there is no state in which this box is absent.
          //
          // **The hue tints the glyph rather than filling a chip behind it, and the tree is
          // why.** A 32px chip reads better in isolation, and at depth 5 it would sit behind
          // 60px of indent: 92px of gutter before the name on a 390px phone. The detail
          // header, which pays no indent, does use the chip.
          WIcon(
            locationIcon(icon),
            className: '${slots['icon']} ${locationGlyphClassName(colour)}',
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
