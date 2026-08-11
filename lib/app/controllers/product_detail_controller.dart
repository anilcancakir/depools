import 'package:magic/magic.dart';

import '../../resources/views/products/product_fixtures.dart';

/// One product with its lots and units, from `api/v1/products/{id}`.
///
/// **Deliberately not part of [ProductController], and not sharing its cache.** Lots and serials
/// exist only in the detail payload, so a single cache keyed by product id would lose them on every
/// list refetch: the list would write a row with no lots over the row the detail screen is drawing,
/// and the screen would empty itself while the user was looking at it. That is the trap
/// `.claude/rules/flutter-app.md` names, and keeping the two apart is what avoids it rather than
/// remembering to merge carefully.
///
/// It holds ONE product at a time, because the screen shows one. Navigating to a second product
/// replaces the first, and [load] returns early when asked for the product it is already showing,
/// so going back and forward does not refetch.
class ProductDetailController extends MagicController
    with MagicStateMixin<ProductListItem> {
  /// The shared instance, keyed by type.
  static ProductDetailController get instance => Magic.findOrPut(ProductDetailController.new);

  String? _loadedId;

  Map<String, String> _locationPaths = const <String, String>{};

  /// Location id to its full hierarchy path, for the per-location sections.
  ///
  /// The PATH rather than the short name, because a detail screen has the width for "Kitchen ›
  /// Fridge" and that is the question it answers: where exactly. A chip in a filter row wants the
  /// short name and gets it from the list controller instead.
  Map<String, String> get locationPaths => _locationPaths;

  /// The id currently held, or null before the first load.
  String? get loadedId => _loadedId;

  /// Fetches one product, unless it is already the one held.
  ///
  /// [force] is for after a write: receiving stock changes the lots this screen is drawing, and
  /// the guard would otherwise serve the pre-write copy.
  Future<void> load(String id, {bool force = false}) async {
    if (!force && _loadedId == id && isSuccess) return;

    _loadedId = id;
    setLoading();

    // Locations alongside the product, because this screen can be reached DIRECTLY by URL with no
    // list behind it, and then nothing else has fetched the names. Without them the per-location
    // sections would be headed by a uuid.
    final List<dynamic> responses = await Future.wait(<Future<dynamic>>[
      Http.get('/locations'),
      Http.get('/products/$id'),
    ]);

    final dynamic locationResponse = responses[0];
    final dynamic productResponse = responses[1];

    if (!locationResponse.successful || !productResponse.successful) {
      setError(Lang.get('screens.products.detail_failed'));

      return;
    }

    final dynamic data = productResponse['data'];

    if (data is! Map) {
      setError(Lang.get('screens.products.detail_failed'));

      return;
    }

    _locationPaths = <String, String>{
      if (locationResponse['data'] is List<dynamic>)
        for (final dynamic row in locationResponse['data'] as List<dynamic>)
          if (row is Map<dynamic, dynamic>)
            row['id'] as String: (row['full_path'] as String?) ?? row['name'] as String,
    };

    setSuccess(
      ProductListItem.fromApi(
        Map<String, dynamic>.from(data),
        locationLabels: _locationPaths,
      ),
    );
  }
}
