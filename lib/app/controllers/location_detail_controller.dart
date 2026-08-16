import 'package:magic/magic.dart';

import '../../resources/views/products/product_fixtures.dart';
import '../models/location_node.dart';
import '../support/mapped_or_null.dart';
import 'location_controller.dart';

/// What is physically on ONE shelf, from `api/v1/products?location_ids[]=`.
///
/// ### Only the products, because the tree is already held
///
/// The node itself and its children come from [LocationController], which holds the whole tree in
/// reading order: a tenant has tens of locations, so asking the server again for one of them would
/// be a request for something already in memory. This controller answers the one question the tree
/// cannot: which products sit directly on this shelf.
///
/// ### Directly, and that is the screen's whole design
///
/// `ProductListQuery` matches a location DIRECTLY rather than including its descendants, and says so
/// in its own docblock. That is exactly what this screen wants: "what is ON this shelf" and "what is
/// in the boxes on it" are two different questions, and folding them would make a location with
/// three sub-locations read as if it physically contained forty items.
///
/// ### One shelf at a time
///
/// Keyed by nothing: opening a second location replaces the first. A map would cache every shelf
/// visited, and a shelf cached ten minutes ago is a stale answer to a question about right now.
class LocationDetailController extends MagicController
    with MagicStateMixin<List<ProductListItem>> {
  /// The shared instance, keyed by type.
  static LocationDetailController get instance =>
      Magic.findOrPut(LocationDetailController.new);

  String? _loadedId;

  /// The location currently held, or null before the first load.
  String? get loadedId => _loadedId;

  /// The products held directly here, or empty while a fetch is in flight.
  List<ProductListItem> get held => rxState ?? const <ProductListItem>[];

  /// Whether the shelf on screen has an answer, as opposed to not having one yet.
  ///
  /// An empty shelf is the NORMAL state of a shelf you are about to fill, and the screen offers
  /// stock-in rather than apologising, so it cannot be shown until it is an answer.
  bool loadedFor(String id) => _loadedId == id && !rxStatus.isLoading;

  /// Fetch one location's products, unless they are already held.
  Future<void> load(String id, {bool force = false}) async {
    if (_loadedId == id && !force) return;

    _loadedId = id;

    setLoading();

    final dynamic response = await Http.get(
      '/products?location_ids[]=${Uri.encodeQueryComponent(id)}',
    );

    // A slower answer for a shelf the user has left must not land on the one they are looking at.
    if (_loadedId != id) return;

    if (!response.successful) {
      setError(response.message ?? Lang.get('screens.location.load_failed'));

      return;
    }

    // **Read off the tree the app already holds**, rather than fetched or passed in. A product row
    // names the places it sits in, and that map is what turns an id into "Kiler › Raf 1". The tree
    // is a singleton and this screen cannot be reached without it, since the header's own name comes
    // from the same list.
    final Map<String, String> labels = <String, String>{
      for (final LocationNode node in LocationController.instance.nodes)
        if (node.id != null) node.id!: node.path,
    };

    final List<ProductListItem>? rows = mappedOrNull<List<ProductListItem>?>(
      () {
        final Object? data = response['data'];

        if (data is! List) return null;

        final List<ProductListItem> found = <ProductListItem>[];

        for (final Object? row in data) {
          if (row is! Map<String, dynamic>) return null;

          found.add(ProductListItem.fromApi(row, locationLabels: labels));
        }

        return found;
      },
      describing: 'the products on a location',
    );

    if (rows == null) {
      setError(Lang.get('screens.location.load_failed'));

      return;
    }

    setSuccess(rows);
  }
}
