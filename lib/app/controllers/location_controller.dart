import 'package:magic/magic.dart';

import '../models/location_node.dart';
import '../support/mapped_or_null.dart';
import '../support/plural.dart';

/// The tenant's location tree, from `api/v1/locations`.
///
/// ### One flat list, ordered by path
///
/// The endpoint returns every location in reading order, so the client never sorts a hierarchy it
/// only has flat rows of. That is also why there is no per-node fetch here: a tenant has tens of
/// locations rather than thousands, and a tree drawn from one request cannot show a parent whose
/// children have not arrived.
///
/// ### The summary line is computed here, not sent
///
/// `LocationResource` carries `stock_count` and nothing about children, so "4 products, 3
/// sub-locations" is assembled from the list itself: children are the rows whose `parent_id` is this
/// row's id, which the flat list already knows. Sending a second count per node would be a query per
/// row for a sentence the client can read off what it already holds.
///
/// It is also the reason the summary is not on the model's `fromApi`: the count needs the whole
/// list, and a model cannot see its siblings.
class LocationController extends MagicController
    with MagicStateMixin<List<LocationNode>>, ValidatesRequests {
  /// The shared instance, keyed by type.
  static LocationController get instance => Magic.findOrPut(LocationController.new);

  /// [create]'s rule set, mirroring `StoreLocationRequest::rules()` by hand.
  ///
  /// `parent_id` (`nullable|uuid`) and `icon` (`nullable|Rule::exists(...)`) carry no client-side
  /// mirror: magic ships no `uuid` or `exists` rule, and approximating either would either accept a
  /// value the server refuses or refuse one it accepts. `colour` mirrors `Rule::in(Location::COLOURS)`
  /// with the same seven hues (`Location::COLOURS`, `backend/app/Models/Location.php`).
  static final Map<String, List<Rule>> _createRules = <String, List<Rule>>{
    'name': <Rule>[Required(), Max(255)],
    'colour': <Rule>[
      In<String>(<String>['slate', 'blue', 'teal', 'green', 'amber', 'red', 'violet']),
    ],
  };

  bool _loaded = false;

  /// The tree, or empty while it is in flight.
  ///
  /// Named rather than left as `rxState`, matching `ProductController.items`: a view reading
  /// `rxState ?? const []` in three places is three chances to forget the fallback.
  List<LocationNode> get nodes => rxState ?? const <LocationNode>[];

  /// Whether a tree has been fetched at all, as opposed to fetched and empty.
  ///
  /// A tenant with no locations is a real state the empty screen is drawn for, so "nothing here" and
  /// "nothing yet" cannot be told apart by an empty list alone.
  bool get loaded => _loaded;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  /// Fetch the tree, unless it is already held.
  ///
  /// [force] after a write, which is the one case where the held copy is known to be stale. Without
  /// the guard, every revisit of the locations tab would refetch a tree that changes a few times a
  /// month.
  Future<void> load({bool force = false}) async {
    if (_loaded && !force) return;

    if (!force) setLoading();

    final dynamic response = await Http.get('/locations');

    if (!response.successful) {
      setError(response.message ?? Lang.get('screens.locations.load_failed'));

      return;
    }

    final List<LocationNode>? nodes = _read(response['data']);

    // **A mapping failure is an ERROR, not an empty tree.** The empty state offers to create a first
    // location, so answering a broken payload with it would tell a tenant who has forty shelves that
    // they have none, and invite them to make a forty-first.
    if (nodes == null) {
      setError(Lang.get('screens.locations.load_failed'));

      return;
    }

    _loaded = true;

    setSuccess(nodes);
  }

  /// Create a location, then reload so the tree shows it.
  ///
  /// Returns null on success, or the server's message. The caller decides how to show it, because a
  /// failed write must NOT put this controller into its error state: that would blank a tree the user
  /// is looking at over a write that changed nothing.
  ///
  /// **`fill(..., strict: true)` then `await save()`**, not a raw `Http.post`: `save()` returns a
  /// bool rather than throwing, so a 422 is read off `node.validationErrors` afterwards rather than
  /// caught. Nothing here nulls `rxState`, unlike the old `handleApiError` path: `rxState` is never
  /// touched by the failure branch, so the tree the user is looking at stays exactly as it was.
  Future<String?> create({
    required String name,
    String? parentId,
    String? icon,
    String? colour,
  }) async {
    try {
      validate(<String, dynamic>{'name': name, 'colour': colour}, _createRules);
    } on ValidationException {
      // validationErrors is already populated and refreshUI() already fired, so the UI already
      // shows the refusal once the form reads hasError()/getError(); this return value is only
      // for the caller's own fallback surface (MagicFeedback.error) until that wiring lands.
      return firstError;
    }

    final LocationNode node = LocationNode()
      ..fill(<String, dynamic>{
        'name': name,
        'parent_id': parentId,
        'icon': icon,
        'colour': colour,
      }, strict: true);

    if (!await node.save()) {
      _applyValidationErrors(node.validationErrors);

      return node.validationError('name') ??
          node.validationError('colour') ??
          Lang.get('screens.location_form.save_failed');
    }

    await load(force: true);

    return null;
  }

  /// Mirrors `ValidatesRequests.setErrorsFromResponse`, for a [LocationNode.save] refusal rather
  /// than a raw `MagicResponse`: `save()` already parsed the server's 422 into `validationErrors`,
  /// so this only moves the first message per field into this controller's own error store.
  void _applyValidationErrors(Map<String, List<String>> errors) {
    validationErrors = <String, String>{
      for (final MapEntry<String, List<String>> entry in errors.entries)
        if (entry.value.isNotEmpty) entry.key: entry.value.first,
    };
    refreshUI();
  }

  /// The three top-level places a first-run tenant is offered.
  ///
  /// `location-assignment.md` makes the empty state a blocker rather than decoration ("no locations
  /// means stock has nowhere to go") and offers either adding one or a starter template. The doc
  /// does not name the rows, so these follow what the empty state's own copy already promises:
  /// "Start with top-level places like Kitchen and Pantry".
  ///
  /// **The names are localised and the icons are not.** A name becomes the tenant's own data and has
  /// to arrive in their language; an icon is a key into a global catalogue that has no language.
  ///
  /// The three icon names are hardcoded, and the risk is worth stating: `store` validates them with
  /// `Rule::exists('icons', 'name')`, so a re-vendor that dropped one would turn a first-run tap
  /// into a 422. All three are among the most used glyphs in the set (measured: `ac_unit` 3228,
  /// `warehouse` 2735, `kitchen` 1576), which is why the risk is accepted rather than designed
  /// around with a lookup the client would have to make first.
  static const List<({String key, String icon, String colour})> _template =
      <({String key, String icon, String colour})>[
        (key: 'screens.locations.template_kitchen', icon: 'kitchen', colour: 'amber'),
        (key: 'screens.locations.template_pantry', icon: 'dining', colour: 'green'),
        (key: 'screens.locations.template_storage', icon: 'warehouse', colour: 'slate'),
      ];

  /// Create the starter template, stopping at the first failure.
  ///
  /// **Stopping rather than carrying on**, because the alternative is a tenant who asked for three
  /// places and got two with no way to tell which is missing. The ones already written stay: they
  /// are real locations the user asked for, and deleting them to make the operation atomic would
  /// need a delete endpoint that does not exist and would throw away work over a partial success.
  ///
  /// The tree is reloaded once at the end rather than after each create, so the screen does not
  /// redraw three times.
  Future<String?> createTemplate() async {
    for (final ({String key, String icon, String colour}) row in _template) {
      final dynamic response = await Http.post('/locations', data: <String, dynamic>{
        'name': Lang.get(row.key),
        'icon': row.icon,
        'colour': row.colour,
      });

      if (!response.successful) {
        await load(force: true);

        return response.message ?? Lang.get('screens.location_form.save_failed');
      }
    }

    await load(force: true);

    return null;
  }

  /// The rows, or null when any of them could not be read.
  List<LocationNode>? _read(Object? data) {
    if (data is! List) return null;

    final List<Map<String, dynamic>> rows = data.whereType<Map<String, dynamic>>().toList();

    if (rows.length != data.length) return null;

    // Children counted from the payload itself, in one pass, so the summary below is a lookup rather
    // than a scan per row.
    final Map<String, int> children = <String, int>{};

    for (final Map<String, dynamic> row in rows) {
      final Object? parent = row['parent_id'];

      if (parent is String) {
        children[parent] = (children[parent] ?? 0) + 1;
      }
    }

    return mappedOrNull<List<LocationNode>?>(
      () {
        final List<LocationNode> nodes = <LocationNode>[];

        for (final Map<String, dynamic> row in rows) {
          final LocationNode? node = LocationNode.fromApi(
            row,
            summarise: (int count) => _summary(count, children[row['id']] ?? 0),
          );

          // **One unreadable row fails the whole tree, unlike a product list.** A tree is a shape
          // rather than a set: a node dropped in the middle orphans everything under it, and the
          // screen would then draw a shelf as a root with no indication anything is missing.
          if (node == null) return null;

          nodes.add(node);
        }

        return nodes;
      },
      describing: 'the location tree',
    );
  }

  /// "4 products · 3 sub-locations", or "Empty".
  ///
  /// **A place holding nothing says so rather than saying "0 products".** A zero reads as a figure
  /// the user should act on, and an empty shelf is an ordinary state: the tree's own filter has a
  /// chip for it.
  String _summary(int products, int children) {
    if (products == 0 && children == 0) {
      return Lang.get('screens.locations.summary_empty');
    }

    final List<String> parts = <String>[
      if (products > 0)
        plural('screens.locations.summary_products', products, <String, dynamic>{'count': products}),
      if (children > 0)
        plural('screens.locations.summary_children', children, <String, dynamic>{'count': children}),
    ];

    return parts.join(' · ');
  }
}
