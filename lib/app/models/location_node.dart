import 'package:flutter/foundation.dart' show immutable;

/// One place in the tenant's location tree, as a screen draws it.
///
/// **Moved here from `location_index_view.dart`, where it was the fixture's shape.** It is now the
/// shape the API answers in too, and a model that three screens read had no business living inside
/// one of them.
///
/// The fixtures stay where they are and keep constructing this: they are the preview catalog's data
/// source, so `/preview` keeps working with no server and no session.
@immutable
class LocationNode {
  /// The row's id, or null for a fixture that never came from the API.
  ///
  /// Nullable for the same reason `ProductListItem.id` is: a preview renders a node nobody can open,
  /// and a screen that navigates checks for null rather than the catalog inventing an id.
  final String? id;

  /// The location's own name.
  final String name;

  /// Depth, 0 for a root.
  final int depth;

  /// Products in the subtree.
  final int productCount;

  /// The already-formatted contents line.
  final String summary;

  /// The full ancestor path, used when the tree is filtered and the indent loses meaning.
  final String path;

  /// The parent's id, or null for a root.
  final String? parentId;

  /// The location's icon NAME, from `locations.icon`.
  ///
  /// **Every node draws one, children included.** A tree where only roots carry a glyph makes the
  /// children look like text under a heading rather than like places, and a shelf is as much a place
  /// as a room is. The column is nullable, so the fallback lives in `location_appearance.dart`
  /// rather than in a condition on the row.
  final String? icon;

  /// The location's hue NAME, from `locations.colour`.
  ///
  /// Also nullable, and also resolved through the same fallback: a location the user never tinted is
  /// neutral rather than absent.
  final String? colour;

  /// Creates a [LocationNode].
  const LocationNode({
    required this.name,
    required this.depth,
    required this.productCount,
    required this.summary,
    required this.path,
    this.id,
    this.parentId,
    this.icon,
    this.colour,
  });

  /// Reads one from `LocationResource`, or null when the payload cannot make a row.
  ///
  /// Null rather than a throw, and null rather than a placeholder: one malformed row in a tree of
  /// forty should cost that row, not the screen, and a node with no name or no id is not a place the
  /// user can be sent to.
  ///
  /// **`depth` is zero-based on both sides and is passed through**, which is worth stating because
  /// it is the kind of thing that reads like it needs converting: `Location::MAX_DEPTH` is 6 and
  /// its own comment says "a root is 0, so a legal tree has seven levels". The row multiplies this
  /// by a gutter width, so an off-by-one here indents the whole tree and nothing complains.
  ///
  /// The form's `_depth` getter is the one place that counts from 1, because it describes the level
  /// a NEW child would land at rather than the level of a row that exists.
  static LocationNode? fromApi(Map<String, dynamic> map, {required String Function(int) summarise}) {
    final Object? id = map['id'];
    final Object? name = map['name'];

    if (id is! String || name is! String || name.trim().isEmpty) {
      return null;
    }

    final int count = map['stock_count'] is num ? (map['stock_count'] as num).toInt() : 0;
    final int depth = map['depth'] is num ? (map['depth'] as num).toInt() : 0;

    return LocationNode(
      id: id,
      name: name.trim(),
      depth: depth < 0 ? 0 : depth,
      productCount: count,
      summary: summarise(count),
      path: map['full_path'] is String ? map['full_path'] as String : name.trim(),
      parentId: map['parent_id'] is String ? map['parent_id'] as String : null,
      icon: map['icon'] is String ? map['icon'] as String : null,
      colour: map['colour'] is String ? map['colour'] as String : null,
    );
  }
}
