import 'package:magic/magic.dart';

import '../../resources/views/products/product_filter_sheet.dart';
import '../../resources/views/products/product_fixtures.dart';
import '../models/product_filter.dart';
import '../support/mapped_or_null.dart';

/// The products list, from `api/v1/products`.
///
/// **This is the first controller in the app, so it is the pattern the other screens copy.**
/// Its shape is `magic_starter`'s own controllers rather than anything invented here: a
/// [MagicController] resolved once through [Magic.findOrPut], [MagicStateMixin] carrying the
/// loading, empty, error and loaded states so the view renders all four from one source, and
/// every request through the [Http] facade so the base URL, the Sanctum bearer and the
/// telescope interceptor come for free.
///
/// ### The filter lives here, not in the view
///
/// It used to live in the view's `State`, which was right while the endpoint answered the whole
/// collection and the view filtered the rows it held. It cannot stay there now that the filter is a
/// query parameter: the rows and the criteria that produced them have to move together, or a rebuild
/// shows one page of "expired" under a chip row that says something else. [apply] is the only way to
/// change it, and it always refetches from the first page.
///
/// ### The shelf moved out
///
/// This class used to hold a second cache for the count screen. That was defensible while a shelf
/// was one list fetched once, and stopped being defensible when the shelf gained its own query,
/// order, cursor, total and failure state: two state machines in one class share nothing but a file.
/// `StockTakeController` owns it now, and the two answer different questions.
class ProductController extends MagicController with MagicStateMixin<List<ProductListItem>> {
  /// How many rows a browse page asks for.
  ///
  /// The server defaults to the same number; sending it makes the page size a decision this file
  /// records rather than one that lives only in PHP.
  static const int _pageSize = 30;

  /// The shared instance, keyed by type.
  ///
  /// Keyed by TYPE means this survives a login and a team switch, so [load] has to be called
  /// again on either. It is not called from here: a controller that reloads itself on an auth
  /// event needs a listener, and wiring one before there is a second reader would be guessing
  /// at where that belongs.
  static ProductController get instance => Magic.findOrPut(ProductController.new);

  List<FilterOption> _locations = const <FilterOption>[];

  Map<String, String> _locationLabels = const <String, String>{};

  ProductFilter _filter = const ProductFilter();

  ProductSort _sort = ProductSort.name;

  String? _cursor;

  int _total = 0;

  int _catalogueTotal = 0;

  bool _loadingMore = false;

  int _loadedPages = 0;

  bool _refreshing = false;

  /// Which request the newest one is, so an older answer cannot overwrite it.
  ///
  /// **A search field with a debounce still races.** Two requests can be in flight when the user
  /// types past the debounce window, and nothing guarantees they come back in order: the answer to
  /// `sü` arriving after the answer to `süt` would leave the list showing the wider result under the
  /// narrower query, with no error anywhere.
  int _requestId = 0;

  Set<String> _stockedLocations = const <String>{};

  /// Location id to name, for anything mapping a product payload into rows.
  ///
  /// Exposed because `StockTakeController` maps its own rows and needs the same labels; fetching
  /// them twice would put two answers to one question in the app.
  Map<String, String> get locationLabels => _locationLabels;

  /// The locations the filter sheet offers, in the order the endpoint returns them.
  ///
  /// That order is the location tree's reading order, which the endpoint guarantees by sorting
  /// on `path`, so the sheet does not re-sort and cannot disagree with the tree screen.
  List<FilterOption> get locations => _locations;

  /// The loaded rows, or an empty list before the first load finishes.
  ///
  /// Empty rather than null so the view can count without a null check on every read. The
  /// distinction the view actually needs is `rxStatus`, not this.
  ///
  /// **Already narrowed.** These are what the server answered for [filter]; there is no wider set
  /// behind them to filter again, and a second client-side pass would only be able to disagree.
  List<ProductListItem> get items => rxState ?? const <ProductListItem>[];

  /// What the loaded rows were fetched with.
  ProductFilter get filter => _filter;

  /// How the loaded rows are ordered.
  ///
  /// Held beside the filter rather than inside it, because a sort is not a criterion: it changes
  /// nothing about WHICH rows match, so folding it into `ProductFilter` would make `activeCount`
  /// count it, `criteria()` render it as a removable chip, and `isEmpty` say a sorted list is
  /// filtered.
  ProductSort get sort => _sort;

  /// How many rows match [filter] in total, not how many are loaded.
  int get total => _total;

  /// How many products the tenant holds with nothing narrowing the list.
  ///
  /// Held separately because it answers a question the current page cannot: "none of your 101
  /// products match" needs the catalogue size while a filter is applied.
  ///
  /// **It used to say "the first load is always unfiltered, so it is known before any filter can be
  /// applied", and URL state made that false.** A shared link mounts the screen with a filter
  /// already on, so the first load is filtered and this was never written: the subtitle read
  /// `11 of 0 products` and the no-matches panel would have claimed the tenant owned nothing. So
  /// [load] fetches it on its own when a filtered load finds it unknown.
  int get catalogueTotal => _catalogueTotal;

  /// How many pages are currently loaded.
  ///
  /// The screen writes this into its own URL so a shared link reproduces the same ROWS rather than a
  /// cursor. A cursor names a position in one ordered result: shared, it drops the reader into the
  /// middle of a list with nothing above it, and points nowhere once that row is renamed or consumed.
  /// A count re-fetches pages one to N, which is the same rows with the top intact.
  int get loadedPages => _loadedPages;

  /// Whether another page exists.
  bool get hasMore => _cursor != null;

  /// Whether that next page is in flight.
  bool get loadingMore => _loadingMore;

  /// Whether the first page is being refetched under rows that are already on screen.
  ///
  /// Distinct from `rxStatus.isLoading`, which replaces the list with skeletons. A filter change on a
  /// list the user is already reading should not blank it out and then redraw, so the rows stay and
  /// this says the answer may still move.
  bool get refreshing => _refreshing;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  /// Replaces the filter and refetches from the first page.
  ///
  /// The cursor is dropped rather than kept, which is the whole reason this is not a setter: a cursor
  /// is a position in ONE ordered result, so carrying it across a filter change would ask the server
  /// to continue a list that no longer exists.
  Future<void> apply(ProductFilter next, {ProductSort? sort}) async {
    final ProductSort nextSort = sort ?? _sort;

    if (next == _filter && nextSort == _sort) return;

    _filter = next;
    _sort = nextSort;

    // The cursor is dropped by `load`, which is what a sort change needs even more than a filter
    // change does: a cursor is a position in ONE ordering, so continuing it under a different one
    // would ask the server to resume a list that was never produced.
    await load();
  }

  /// Fetches the locations and the first page of products, and maps them into rows.
  Future<void> load() async {
    final int request = ++_requestId;

    // Any page in flight belongs to the filter being replaced, so it is abandoned here rather than
    // waited for. `loadMore` sees the bumped request id and drops its answer; this is the half that
    // makes sure the flag it set does not outlive it.
    _loadingMore = false;

    // Skeletons only when there is nothing to show. Replacing a list the user is reading with
    // placeholders on every filter change is a flash for no information: the rows are still true
    // until the answer lands, and [refreshing] is what says more is coming.
    if (rxState == null) {
      setLoading();
    } else {
      _refreshing = true;
      refreshUI();
    }

    if (_locations.isEmpty && !await _loadLocations()) {
      if (request != _requestId) return;

      _refreshing = false;
      setError(Lang.get('screens.products.load_failed'));

      return;
    }

    final dynamic response = await Http.get('/products?${_query()}');

    // A newer request started while this one was in flight, so this answer is stale by definition.
    // Dropped rather than merged: it was asked under a filter the user has already moved past.
    if (request != _requestId) return;

    _refreshing = false;

    if (!response.successful) {
      setError(Lang.get('screens.products.load_failed'));

      return;
    }

    final List<ProductListItem>? rows = _mapOrNull(response['data']);

    // A payload this client cannot read is a failed load, not a screen that waits.
    if (rows == null) {
      setError(Lang.get('screens.products.load_failed'));

      return;
    }

    _cursor = _cursorOf(response);
    _total = _totalOf(response) ?? rows.length;
    _loadedPages = 1;

    if (_filter.isEmpty) {
      _catalogueTotal = _total;
    } else if (_catalogueTotal == 0) {
      // One extra count, once, and only on the path that cannot get it for free: a screen mounted
      // straight from a filtered link. An ordinary visit loads unfiltered first and never comes here.
      _catalogueTotal = await countFor(const ProductFilter()) ?? 0;
    }

    // `setEmpty` rather than a success with no rows, because the view shows a different screen
    // for "this tenant has no products yet" than for "the filter matched none of them", and it
    // cannot tell the two apart from an empty list alone. With the filter applied on the SERVER the
    // filter itself is what distinguishes them, and it is the only thing that can.
    if (rows.isEmpty && _filter.isEmpty) {
      setEmpty();

      return;
    }

    setSuccess(rows);
  }

  /// Appends the next page, if there is one.
  ///
  /// Guarded on both the cursor and the in-flight flag: the scroll trigger fires repeatedly while the
  /// user is near the bottom, so without the guard one gesture would ask for the same page several
  /// times and append it several times.
  Future<void> loadMore() async {
    if (_cursor == null || _loadingMore || _refreshing) return;

    final int request = _requestId;
    final String cursor = _cursor!;

    _loadingMore = true;
    refreshUI();

    final dynamic response = await Http.get('/products?${_query(cursor: cursor)}');

    // A filter change during the fetch invalidates this page: appending it would mix rows selected
    // under two different criteria into one list.
    //
    // **Cleared BEFORE the return, and that ordering is the whole content of this line.** Returning
    // with the flag still set leaves it set forever: nothing else resets it, so the guard at the top
    // of this method refuses every later page and the footer stays on its spinner. One filter change
    // landing while a page was in flight would have killed pagination for the rest of the session,
    // and the screen would have looked like a list that simply ended.
    _loadingMore = false;

    if (request != _requestId) return;

    if (!response.successful) {
      // The page the user already has stays. A failed "load more" is not a failed screen, and
      // replacing a readable list with an error panel because the fourth page timed out would lose
      // what they were looking at.
      refreshUI();

      return;
    }

    final List<ProductListItem>? more = _mapOrNull(response['data']);

    // The page the user already has stays, for the same reason a failed request leaves it: an
    // unreadable FOURTH page is not a reason to replace a readable list with an error panel.
    if (more == null) {
      refreshUI();

      return;
    }

    _cursor = _cursorOf(response);
    _loadedPages++;

    setSuccess(<ProductListItem>[...items, ...more]);
  }

  /// Loads the first page and then [count] minus one more, for a link that was shared mid-list.
  ///
  /// Sequential rather than parallel, because each page needs the cursor the previous one answered
  /// with. Stops early when the list runs out, so a link written against a longer list still lands
  /// on a complete one rather than hanging on a page that no longer exists.
  Future<void> loadPages(int count) async {
    // **Only when nothing is loaded**, because the caller has usually just loaded page one. The URL
    // flow applies the filter first, which loads, and then asks for the page count: an unconditional
    // `load()` here fetched page one a second time, so every shared deep link paid for an identical
    // request nobody read.
    if (rxState == null) await load();

    // Counted from what IS loaded rather than from one, so this extends a list instead of assuming
    // it starts at a page.
    for (int i = loadedPages; i < count && hasMore; i++) {
      await loadMore();
    }
  }

  /// How many rows a draft filter would match, without applying it.
  ///
  /// The filter sheet previews this number as the user toggles, and with the filter running on the
  /// server it cannot be counted locally any more. `per_page=1` because only `meta.total` is being
  /// read; the one row is what the endpoint costs at its minimum rather than something used.
  ///
  /// Null when the request fails, so the sheet can leave its previous number alone rather than
  /// showing a zero that means "the network is down".
  Future<int?> countFor(ProductFilter draft) async {
    final dynamic response = await Http.get(
      '/products?${draft.toQueryString(extra: <String, Object?>{'per_page': 1})}',
    );

    if (!response.successful) return null;

    return _totalOf(response);
  }

  /// Whether one location holds any stock at all.
  ///
  /// From the location payload's own `stock_count`, not from the loaded products. The count screen
  /// needs this to open on a shelf with something on it, and it cannot answer it from a product
  /// list that is one page: a full shelf whose rows sit on page three would read as empty.
  bool holdsStock(String locationId) => _stockedLocations.contains(locationId);

  /// The query string for one browse request.
  String _query({String? cursor}) => _filter.toQueryString(
    extra: <String, Object?>{
      // Null for the default, so an unsorted request stays as short as it was and the server's own
      // default is the single definition of "no sort given".
      'sort': ?_sort.wire,
      'per_page': _pageSize,
      'cursor': ?cursor,
    },
  );

  /// Fetches the locations, returning whether it worked.
  Future<bool> _loadLocations() async {
    final dynamic response = await Http.get('/locations');

    if (!response.successful) return false;

    final List<Map<String, dynamic>> rows = _rows(response['data']);

    _locations = _toFilterOptions(rows);
    _locationLabels = <String, String>{
      for (final FilterOption option in _locations) option.id: option.label,
    };
    _stockedLocations = <String>{
      for (final Map<String, dynamic> row in rows)
        if ((row['stock_count'] as int? ?? 0) > 0) row['id'] as String,
    };

    return true;
  }

  /// [_map], with a row this client cannot read answered as null rather than thrown.
  ///
  /// The reasoning, and the measurement behind it, is in [mappedOrNull].
  List<ProductListItem>? _mapOrNull(Object? data) {
    return mappedOrNull(() => _map(data), describing: 'a product list payload');
  }

  /// Maps a `data` array into rows.
  List<ProductListItem> _map(Object? data) {
    // ONE reference date for the page. `fromApi` defaults it to `DateTime.now()`, so mapping
    // eleven rows across midnight would compute two different todays and the expiry counts would
    // disagree by a day within one list.
    final DateTime today = DateTime.now();

    return <ProductListItem>[
      for (final Map<String, dynamic> row in _rows(data))
        ProductListItem.fromApi(row, locationLabels: _locationLabels, today: today),
    ];
  }

  /// `meta.next_cursor`, or null when this is the last page.
  String? _cursorOf(dynamic response) {
    final dynamic meta = response['meta'];
    final dynamic cursor = meta is Map<dynamic, dynamic> ? meta['next_cursor'] : null;

    // An empty string is not a cursor. Laravel sends null, and a defensive read costs nothing next
    // to a loop that would ask for `cursor=` forever.
    return cursor is String && cursor.isNotEmpty ? cursor : null;
  }

  /// `meta.total`, or null when the response carries none.
  int? _totalOf(dynamic response) {
    final dynamic meta = response['meta'];

    return meta is Map<dynamic, dynamic> ? meta['total'] as int? : null;
  }

  List<FilterOption> _toFilterOptions(List<Map<String, dynamic>> rows) => <FilterOption>[
    for (final Map<String, dynamic> row in rows)
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
