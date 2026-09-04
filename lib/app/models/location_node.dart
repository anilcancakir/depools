import 'package:magic/magic.dart';

/// One place in the tenant's location tree, as `api/v1/locations` sends it.
///
/// **Moved here from `location_index_view.dart`, where it was the fixture's shape.** It is now the
/// shape the API answers in too, and a model that three screens read had no business living inside
/// one of them.
///
/// A magic [Model] rather than a value class: `create` writes through [LocationController], whose
/// fields mirror `StoreLocationRequest::rules()` and are declared in [fillable], so a schema drift
/// between the two rule sets throws `MassAssignmentException` (`fill(..., strict: true)`) instead
/// of silently dropping a field.
///
/// The fixtures stay where they are and keep constructing this: they are the preview catalog's data
/// source, so `/preview` keeps working with no server and no session.
class LocationNode extends Model with InteractsWithPersistence {
  /// The table associated with the model.
  @override
  String get table => 'locations';

  /// The API resource for remote operations.
  @override
  String get resource => 'locations';

  /// Whether the primary key is auto-incrementing.
  ///
  /// Set to false because this app uses string UUIDs as primary keys.
  @override
  bool get incrementing => false;

  /// The attributes that are mass assignable, mirroring `StoreLocationRequest::rules()`.
  ///
  /// Every other attribute here (`id`, `stock_count`, the derived `summary`) is server-computed or
  /// client-derived rather than sent in a create request; `team_id` never appears here either, per
  /// this app's own tenancy invariant.
  @override
  List<String> get fillable => <String>['name', 'parent_id', 'icon', 'colour'];

  /// The attributes that should be cast.
  @override
  Map<String, String> get casts => {};

  // ---------------------------------------------------------------------------
  // Typed Accessors
  // ---------------------------------------------------------------------------

  /// The row's id, or null for a fixture that never came from the API.
  ///
  /// Nullable for the same reason `ProductListItem.id` is: a preview renders a node nobody can open,
  /// and a screen that navigates checks for null rather than the catalog inventing an id.
  @override
  String? get id => get<String>('id');

  /// The location's own name.
  String get name => get<String>('name') ?? '';

  /// Depth, 0 for a root.
  int get depth => get<int>('depth') ?? 0;

  /// Products in the subtree, from `locations.stock_count`.
  int get productCount => get<int>('stock_count') ?? 0;

  /// The already-formatted contents line.
  String get summary => get<String>('summary') ?? '';

  /// The full ancestor path, used when the tree is filtered and the indent loses meaning.
  String get path => get<String>('full_path') ?? name;

  /// The parent's id, or null for a root.
  String? get parentId => get<String>('parent_id');

  /// The location's icon NAME, from `locations.icon`.
  ///
  /// **Every node draws one, children included.** A tree where only roots carry a glyph makes the
  /// children look like text under a heading rather than like places, and a shelf is as much a place
  /// as a room is. The column is nullable, so the fallback lives in `location_appearance.dart`
  /// rather than in a condition on the row.
  String? get icon => get<String>('icon');

  /// The location's hue NAME, from `locations.colour`.
  ///
  /// Also nullable, and also resolved through the same fallback: a location the user never tinted is
  /// neutral rather than absent.
  String? get colour => get<String>('colour');

  // ---------------------------------------------------------------------------
  // Construction
  // ---------------------------------------------------------------------------

  /// An unfilled node, for `..fill(validated, strict: true)` on a write.
  ///
  /// **Declared explicitly, not left implicit.** Once a class declares any other constructor
  /// (`_raw`, `of`), Dart stops auto-generating the plain unnamed one; a controller's write path
  /// needs it as the starting point for a mass-assignment guarded fill.
  LocationNode();

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

    return LocationNode._raw(<String, dynamic>{
      'id': id,
      'name': name.trim(),
      'depth': depth < 0 ? 0 : depth,
      'stock_count': count,
      'summary': summarise(count),
      'full_path': map['full_path'] is String ? map['full_path'] as String : name.trim(),
      'parent_id': map['parent_id'] is String ? map['parent_id'] as String : null,
      'icon': map['icon'] is String ? map['icon'] as String : null,
      'colour': map['colour'] is String ? map['colour'] as String : null,
    });
  }

  /// Builds a node from already-known fields, for a fixture or a test.
  ///
  /// Bypasses [fillable] the way `User.fromMap` does: this is not the mass-assignment path, it is
  /// hydration from data the caller already trusts.
  factory LocationNode.of({
    required String name,
    required int depth,
    required int productCount,
    required String summary,
    required String path,
    String? id,
    String? parentId,
    String? icon,
    String? colour,
  }) {
    return LocationNode._raw(<String, dynamic>{
      'id': id,
      'name': name,
      'depth': depth,
      'stock_count': productCount,
      'summary': summary,
      'full_path': path,
      'parent_id': parentId,
      'icon': icon,
      'colour': colour,
    });
  }

  LocationNode._raw(Map<String, dynamic> attributes) {
    setRawAttributes(attributes, sync: true);
    exists = attributes['id'] != null;
  }
}
