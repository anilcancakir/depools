import 'package:magic/magic.dart';

import '../../resources/views/products/product_fixtures.dart';
import '../support/mapped_or_null.dart';
import 'product_controller.dart';

/// What is short, from `api/v1/running-low`.
///
/// ### Nothing is filtered here
///
/// The server decides membership, because the predicate needs three things a client cannot hold:
/// the whole tenant's projection, the consumption rate, and how often this tenant shops. So this
/// carries rows and a status, and the grouping into the out-of-stock group and the three tiers is
/// the view's, exactly as `ExpiringController` leaves the location grouping to `DatesView`.
///
/// ### The empty list is the good outcome, so it cannot be shown early
///
/// "Nothing is short" is what a user wants to read, which makes it the one wrong thing to say while
/// the request is in flight. [loaded] separates "answered and empty" from "not answered yet", and
/// the view reads that rather than the length of the list.
class RunningLowController extends MagicController with MagicStateMixin<List<ProductListItem>> {
  /// The shared instance, keyed by type.
  static RunningLowController get instance => Magic.findOrPut(RunningLowController.new);

  bool _loaded = false;

  /// The short products, most urgent first, or empty while the first fetch is in flight.
  List<ProductListItem> get rows => rxState ?? const <ProductListItem>[];

  /// Whether the server has answered at all, as opposed to answered with nothing.
  bool get loaded => _loaded;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  /// Fetch the shortages.
  ///
  /// Always a request rather than a cached read, because this list changes on every stock movement
  /// the user makes: buying the thing the screen just told them to buy is the expected next action,
  /// and coming back to a stale row saying it is still short would be the screen contradicting the
  /// receipt the user just recorded.
  Future<void> load() async {
    setLoading();

    final dynamic response = await Http.get('/running-low');

    if (!response.successful) {
      setError(response.message ?? Lang.get('screens.running_low.load_failed'));

      return;
    }

    final List<ProductListItem>? rows = mappedOrNull<List<ProductListItem>?>(
      () {
        final Object? data = response['data'];

        if (data is! List) return null;

        final List<ProductListItem> found = <ProductListItem>[];

        for (final Object? row in data) {
          if (row is! Map<String, dynamic>) return null;

          // The labels ProductController already fetched, rather than a second request for the
          // same table. Empty before that controller has run, which costs this screen nothing:
          // a running-low row shows the target and the cover, never where the stock is, because
          // "you are nearly out of milk" is not a question about which shelf.
          found.add(
            ProductListItem.fromApi(
              row,
              locationLabels: ProductController.instance.locationLabels,
            ),
          );
        }

        return found;
      },
      describing: 'the running-low list',
    );

    if (rows == null) {
      setError(Lang.get('screens.running_low.load_failed'));

      return;
    }

    _loaded = true;

    setSuccess(rows);
  }
}
