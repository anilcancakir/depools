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
  Map<String, String> _locationNames = const <String, String>{};

  /// Location id to its full hierarchy path, for the per-location sections.
  ///
  /// The PATH answers "where exactly", which is what a detail screen has the width for.
  Map<String, String> get locationPaths => _locationPaths;

  /// Location id to its short name, for a sentence rather than a row.
  ///
  /// Both are kept because `FilterOption` distinguishes them and the sheets rely on that: a picker
  /// row wants "Kitchen › Fridge" and a sentence wants "Fridge". Filling the short one with the path
  /// made the move sheet's confirmation read "Afterwards Kitchen › Fridge and Kitchen are both
  /// updated", the long form in the one place the short form exists for.
  Map<String, String> get locationNames => _locationNames;

  /// The id currently held, or null before the first load.
  String? get loadedId => _loadedId;

  /// Brings stock in, then reloads so the screen shows what the ledger now says.
  ///
  /// Returns null on success, or the server's message. The caller decides how to show it, because a
  /// failed write must NOT put this controller into its error state: that would blank a screen the
  /// user is looking at over a write that changed nothing.
  ///
  /// The reload is `force: true`, because the guard exists to stop a revisit refetching and this is
  /// the one case where the held copy is known to be stale: the lots it is drawing are exactly what
  /// just changed.
  Future<String?> receive({
    required String productId,
    required String locationId,
    required num quantity,
    String? expiresAt,
    String? lotCode,
  }) {
    return _write(productId, '/stock/receive', <String, dynamic>{
      'location_id': locationId,
      'quantity': quantity,
      'expires_at': ?expiresAt,
      if (lotCode != null && lotCode.isNotEmpty) 'lot_code': lotCode,
    });
  }

  /// Takes stock out, FEFO deciding which lots it comes from, then reloads.
  ///
  /// [reason] has to be one the endpoint accepts as an OUTFLOW: `consumption`, `waste` or
  /// `return`. A stock-take correction and a data correction are ledger reasons too, and they are
  /// deliberately NOT writable here, because either can be positive: they are not outflows and
  /// `StockWriter::consume` refuses them by design. The count screen owns that path.
  Future<String?> consume({
    required String productId,
    required String locationId,
    required num quantity,
    required String reason,
  }) {
    return _write(productId, '/stock/consume', <String, dynamic>{
      'location_id': locationId,
      'quantity': quantity,
      'reason': reason,
    });
  }

  /// Moves stock between two locations, then reloads.
  ///
  /// One call, not an out and an in. A transfer is a PAIR of movements the writer appends together,
  /// and splitting it client-side would leave a window where the stock exists in neither place.
  Future<String?> transfer({
    required String productId,
    required String fromLocationId,
    required String toLocationId,
    required num quantity,
  }) {
    return _write(productId, '/stock/transfer', <String, dynamic>{
      'from_location_id': fromLocationId,
      'to_location_id': toLocationId,
      'quantity': quantity,
    });
  }

  /// Posts one movement and reloads on success. Returns null, or the server's message.
  ///
  /// Extracted on the third caller rather than the first. All three answer 422 the same way, with
  /// `message` plus per-field `errors`, and the writer's own refusals ("not enough stock at the
  /// source") arrive through the same shape, so one reader is right for all of them.
  ///
  /// The failure is RETURNED rather than set as the controller's error state: blanking a screen the
  /// user is reading, over a write that changed nothing, is worse than the failure. The reload is
  /// `force: true`, because the lots on screen are exactly what just changed.
  Future<String?> _write(String productId, String path, Map<String, dynamic> body) async {
    final response = await Http.post(path, data: <String, dynamic>{
      'product_id': productId,
      ...body,
    });

    if (!response.successful) {
      // The server's own sentence, because it names the reason. Replacing it with a generic line
      // throws away the only useful part of a refusal.
      final dynamic message = response['message'];

      // Generic on purpose. This method serves receive, consume and transfer, so naming one of
      // them made a failed MOVE say "Could not add the stock". The server's own sentence is
      // preferred above; this is only the case where it sent none.
      return message is String && message.isNotEmpty
          ? message
          : Lang.get('screens.product.write_failed');
    }

    await load(productId, force: true);

    return null;
  }

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
      // Encoded, even though an id is a uuid today. It arrives from a route parameter, so the one
      // thing that must not depend on trust is whether it can break out of the path.
      Http.get('/products/${Uri.encodeComponent(id)}'),
    ]);

    final dynamic locationResponse = responses[0];
    final dynamic productResponse = responses[1];

    if (!locationResponse.successful || !productResponse.successful) {
      if (_loadedId == id) setError(Lang.get('screens.products.detail_failed'));

      return;
    }

    final dynamic data = productResponse['data'];

    if (data is! Map) {
      if (_loadedId == id) setError(Lang.get('screens.products.detail_failed'));

      return;
    }

    final List<Map<String, dynamic>> locationRows = <Map<String, dynamic>>[
      if (locationResponse['data'] is List<dynamic>)
        for (final dynamic row in locationResponse['data'] as List<dynamic>)
          if (row is Map<dynamic, dynamic>) Map<String, dynamic>.from(row),
    ];

    _locationPaths = <String, String>{
      for (final Map<String, dynamic> row in locationRows)
        row['id'] as String: (row['full_path'] as String?) ?? row['name'] as String,
    };

    _locationNames = <String, String>{
      for (final Map<String, dynamic> row in locationRows)
        row['id'] as String: row['name'] as String,
    };

    // The LATEST request wins. Navigating product to product starts a second load before the
    // first returns, and responses do not have to come back in order: the earlier one landing last
    // would write the previous product into `rxState` while `_loadedId` already named the new one,
    // so the guard at the top would never refetch it and the screen would sit on the wrong product.
    if (_loadedId != id) return;

    setSuccess(
      ProductListItem.fromApi(
        Map<String, dynamic>.from(data),
        locationLabels: _locationPaths,
        // ONE reference date for the whole payload, the same fix `ProductController` already
        // carries. This screen derives more dates than the list does (the product's own, each
        // lot's binding date, each serial's warranty), and each mapper defaults to
        // `DateTime.now()` on its own, so a payload mapped across midnight would disagree with
        // itself by a day WITHIN one screen: a badge saying two days above a lot saying three.
        today: DateTime.now(),
      ),
    );
  }
}
