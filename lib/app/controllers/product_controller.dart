import 'package:magic/magic.dart';

import '../../resources/views/products/product_filter_sheet.dart';
import '../../resources/views/products/product_fixtures.dart';

/// The products list, from `api/v1/products`.
///
/// **This is the first controller in the app, so it is the pattern the other screens copy.**
/// Its shape is `magic_starter`'s own controllers rather than anything invented here: a
/// [MagicController] resolved once through [Magic.findOrPut], [MagicStateMixin] carrying the
/// loading, empty, error and loaded states so the view renders all four from one source, and
/// every request through the [Http] facade so the base URL, the Sanctum bearer and the
/// telescope interceptor come for free.
///
/// ### Two requests, once per page
///
/// The payload carries location IDs and the row prints location names, so the locations are
/// fetched alongside the products and resolved into a map the mapping reads. Both go out in
/// one [Future.wait]: sequentially the screen waits for the slower one twice.
///
/// ### What it does NOT do yet
///
/// No pagination. The view already renders a loading-more footer and documents that the list
/// is cursor-paginated rather than offset, and the endpoint currently answers the whole
/// collection, so the cursor is a change on both sides and belongs with the endpoint that
/// grows one. Filtering stays in the view against the loaded rows, which is what keeps the
/// filter sheet's count and the list from disagreeing.
class ProductController extends MagicController with MagicStateMixin<List<ProductListItem>> {
  /// The shared instance, keyed by type.
  ///
  /// Keyed by TYPE means this survives a login and a team switch, so [load] has to be called
  /// again on either. It is not called from here: a controller that reloads itself on an auth
  /// event needs a listener, and wiring one before there is a second reader would be guessing
  /// at where that belongs.
  static ProductController get instance => Magic.findOrPut(ProductController.new);

  List<FilterOption> _locations = const <FilterOption>[];

  /// The locations the filter sheet offers, in the order the endpoint returns them.
  ///
  /// That order is the location tree's reading order, which the endpoint guarantees by sorting
  /// on `path`, so the sheet does not re-sort and cannot disagree with the tree screen.
  List<FilterOption> get locations => _locations;

  /// The loaded rows, or an empty list before the first load finishes.
  ///
  /// Empty rather than null so the view can filter and count without a null check on every
  /// read. The distinction the view actually needs is `rxStatus`, not this.
  List<ProductListItem> get items => rxState ?? const <ProductListItem>[];

  @override
  void onInit() {
    super.onInit();
    load();
  }

  /// Fetches the locations and the products, and maps them into rows.
  Future<void> load() async {
    setLoading();

    final List<dynamic> responses = await Future.wait(<Future<dynamic>>[
      Http.get('/locations'),
      Http.get('/products'),
    ]);

    final dynamic locationResponse = responses[0];
    final dynamic productResponse = responses[1];

    if (!locationResponse.successful || !productResponse.successful) {
      setError(Lang.get('screens.products.load_failed'));

      return;
    }

    _locations = _toFilterOptions(locationResponse['data']);

    final Map<String, String> labels = <String, String>{
      for (final FilterOption option in _locations) option.id: option.label,
    };

    // ONE reference date for the page. `fromApi` defaults it to `DateTime.now()`, so mapping
    // eleven rows across midnight would compute two different todays and the expiry counts would
    // disagree by a day within one list.
    final DateTime today = DateTime.now();

    final List<ProductListItem> rows = <ProductListItem>[
      for (final Map<String, dynamic> row in _rows(productResponse['data']))
        ProductListItem.fromApi(row, locationLabels: labels, today: today),
    ];

    // `setEmpty` rather than a success with no rows, because the view shows a different screen
    // for "this tenant has no products yet" than for "the filter matched none of them", and it
    // cannot tell the two apart from an empty list alone.
    if (rows.isEmpty) {
      setEmpty();

      return;
    }

    setSuccess(rows);
  }

  List<FilterOption> _toFilterOptions(Object? data) => <FilterOption>[
    for (final Map<String, dynamic> row in _rows(data))
      FilterOption(
        id: row['id'] as String,
        label: row['name'] as String,
        // The materialised path, which is what makes a nested location legible in a chip: two
        // shelves called `Shelf A` are only distinguishable by what is above them. The endpoint
        // calls it `full_path`, because `path` there is the storage form with its delimiters.
        path: row['full_path'] as String?,
      ),
  ];

  List<Map<String, dynamic>> _rows(Object? data) => <Map<String, dynamic>>[
    if (data is List<dynamic>)
      for (final dynamic row in data)
        if (row is Map<dynamic, dynamic>) Map<String, dynamic>.from(row),
  ];
}
