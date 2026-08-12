import 'package:magic/magic.dart';

import '../../resources/views/products/count_line.dart';
import '../../resources/views/products/product_filter_sheet.dart';
import '../../resources/views/products/product_fixtures.dart';
import '../models/product_filter.dart';

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
/// ### Two caches, two questions
///
/// [items] is the browse list: one filtered page, extended by [loadMore]. [shelf] is every product at
/// one location, which is a different question and cannot be served from a page. The count screen
/// needs the whole shelf to build its sheet, and reading a 30-row page instead would silently drop
/// rows from a count: the sheet would look complete and be short. Keeping them apart is what makes
/// each one able to be right.
class ProductController extends MagicController with MagicStateMixin<List<ProductListItem>> {
  /// How many rows a browse page asks for.
  ///
  /// The server defaults to the same number; sending it makes the page size a decision this file
  /// records rather than one that lives only in PHP.
  static const int _pageSize = 30;

  /// How many rows a shelf sweep asks for per request, which is the endpoint's own ceiling.
  static const int _shelfPageSize = 100;

  /// How many shelf pages to walk before giving up.
  ///
  /// A stop condition rather than a limit anybody should reach: fifty pages is five thousand products
  /// at ONE location. Without it a server that kept answering with a cursor would loop forever, and
  /// an infinite loop inside a screen's first paint is the worst way to find that out.
  static const int _shelfPageLimit = 50;

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

  final Map<String, List<ProductListItem>> _shelves = <String, List<ProductListItem>>{};

  final Set<String> _shelvesInFlight = <String>{};

  /// Locations whose sweep failed, so a screen rendering from `build` cannot retry it every frame.
  ///
  /// **Without this the retry is a loop.** The count screen asks for its shelf from `build`, because
  /// which shelf it needs is only known once the locations arrive; on a failure there would be no
  /// cached answer, so the next frame would ask again, and a server that is down would be asked sixty
  /// times a second. A recorded failure is what turns that into one request plus a button.
  final Set<String> _shelfFailures = <String>{};

  Set<String> _stockedLocations = const <String>{};

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
  Future<void> apply(ProductFilter next) async {
    if (next == _filter) return;

    _filter = next;

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

    final List<ProductListItem> rows = _map(response['data']);

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

    _cursor = _cursorOf(response);
    _loadedPages++;

    setSuccess(<ProductListItem>[...items, ..._map(response['data'])]);
  }

  /// Loads the first page and then [count] minus one more, for a link that was shared mid-list.
  ///
  /// Sequential rather than parallel, because each page needs the cursor the previous one answered
  /// with. Stops early when the list runs out, so a link written against a longer list still lands
  /// on a complete one rather than hanging on a page that no longer exists.
  Future<void> loadPages(int count) async {
    await load();

    for (int i = 1; i < count && hasMore; i++) {
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
  /// needs this to open on a shelf with something on it, and it used to answer the question by
  /// scanning the products it held: correct while that was the whole catalogue, and wrong the moment
  /// it became one page, because a full shelf whose rows sit on page three would have read as empty.
  bool holdsStock(String locationId) => _stockedLocations.contains(locationId);

  /// Every product at one location, or an empty list until [loadShelf] has answered.
  List<ProductListItem> shelf(String locationId) =>
      _shelves[locationId] ?? const <ProductListItem>[];

  /// Whether [shelf] has an answer for this location yet.
  bool hasShelf(String locationId) => _shelves.containsKey(locationId);

  /// Whether the last sweep of this location failed.
  bool shelfFailed(String locationId) => _shelfFailures.contains(locationId);

  /// Fetches every product at one location, walking the cursor to the end.
  ///
  /// **The count screen needs the whole shelf and not a page of it.** A count is scoped to one
  /// location and a person counts it in one pass, so a sheet built from the first thirty rows would
  /// be short with nothing on screen saying so, and every product past the thirtieth would silently
  /// keep whatever balance it had. That is the one failure mode a ledger cannot tolerate quietly.
  ///
  /// Cached per location and re-fetched only when asked, because the sheet is built once per visit
  /// and a commit is what invalidates it.
  Future<void> loadShelf(String locationId, {bool force = false}) async {
    if (locationId.isEmpty) return;
    if (_shelvesInFlight.contains(locationId)) return;
    if (!force && (_shelves.containsKey(locationId) || _shelfFailures.contains(locationId))) return;

    _shelvesInFlight.add(locationId);
    _shelfFailures.remove(locationId);

    if (_locations.isEmpty) await _loadLocations();

    final ProductFilter at = ProductFilter(locationIds: <String>{locationId});
    final List<ProductListItem> rows = <ProductListItem>[];
    String? cursor;
    int pages = 0;

    do {
      final dynamic response = await Http.get(
        '/products?${at.toQueryString(extra: <String, Object?>{
          'per_page': _shelfPageSize,
          'cursor': ?cursor,
        })}',
      );

      if (!response.successful) {
        // Recorded rather than left absent, so the screen can offer a retry instead of asking again
        // on the next frame. A partly-walked shelf is discarded with it: half a shelf presented as a
        // count sheet is worse than none, because nothing on it would say it was half.
        _shelvesInFlight.remove(locationId);
        _shelfFailures.add(locationId);
        refreshUI();

        return;
      }

      rows.addAll(_map(response['data']));
      cursor = _cursorOf(response);
      pages++;
    } while (cursor != null && pages < _shelfPageLimit);

    // **A shelf that ran out of pages is a FAILURE, not a shelf.** Caching what was walked so far
    // would hand the count screen a sheet that is short by exactly the rows nobody reached, with
    // nothing on screen saying so, which is the failure this whole method exists to prevent: it
    // would have been the page-sized sheet again, only bigger. The limit is a stop condition rather
    // than a size anyone should meet, so meeting it means something is wrong upstream and the honest
    // answer is the error panel with its retry.
    if (cursor != null) {
      _shelvesInFlight.remove(locationId);
      _shelfFailures.add(locationId);
      refreshUI();

      return;
    }

    _shelves[locationId] = rows;
    _shelvesInFlight.remove(locationId);
    refreshUI();
  }

  /// Commits a physical count of one location, then reloads what it changed (D59).
  ///
  /// ### Why the count commit lives on the list controller
  ///
  /// Because this is the cache it invalidates. The count screen reads its lines and its expected
  /// figures from exactly these rows, and a commit changes the balance behind them, so the write and
  /// the data it falsifies belong to one owner. `ProductDetailController` holds `receive`, `consume`
  /// and `transfer` for the same reason.
  ///
  /// ### The counts are keyed by product id, not by name
  ///
  /// Two products can share a name, and with real data one of them did: keying the typed figures by
  /// name would let a count of one write itself onto the other.
  ///
  /// A per-line refusal is not a failure. The endpoint commits every writable line and names the
  /// rest, so this returns the whole answer and lets the screen decide what is still unfinished.
  Future<CountCommit> commitCount(String locationId, Map<String, num> counted) async {
    final dynamic response = await Http.post(
      '/stock/count',
      data: <String, dynamic>{
        'location_id': locationId,
        'lines': <Map<String, dynamic>>[
          for (final MapEntry<String, num> entry in counted.entries)
            <String, dynamic>{'product_id': entry.key, 'counted_quantity': entry.value},
        ],
      },
    );

    if (!response.successful) {
      final dynamic message = response['message'];

      return CountCommit.failed(
        message is String && message.isNotEmpty
            ? message
            : Lang.get('screens.stock_take.commit_failed'),
      );
    }

    final dynamic data = response['data'];
    final List<CountResult> lines = <CountResult>[];

    for (final Map<String, dynamic> row in _rows(data is Map<dynamic, dynamic> ? data['lines'] : null)) {
      final CountOutcome? outcome = _outcome(row['outcome'] as String?);

      // An outcome this build does not know means the server answered in a vocabulary added after it.
      // Failing the whole commit is the honest reading: mapping the unknown onto `matched` would tell
      // the user a row is finished, and onto `needsDate` would send them to fix a row that was fine.
      if (outcome == null) {
        return CountCommit.failed(Lang.get('screens.stock_take.commit_failed'));
      }

      lines.add(
        CountResult(
          productId: row['product_id'] as String,
          outcome: outcome,
          // `decimal(_, 3)` travels as the string `'-1.000'`, not as a number, so reading it
          // directly would compare a String against a num and silently fail every threshold.
          delta: ProductListItem.toNumOrNull(row['delta']) ?? 0,
        ),
      );
    }

    // **A 200 that does not answer every line is a failure, not an empty success.** Without this a
    // response whose `data.lines` was missing or short parsed into an empty list, which has no
    // unfinished rows, so the screen showed a success toast and navigated away from a shelf it had
    // not actually committed. On a ledger that is the worst shape of bug available: the user believes
    // the count landed and nothing says otherwise.
    //
    // Compared by SET rather than by count, so a response echoing one product twice and omitting
    // another cannot pass by arithmetic.
    final Set<String> answered = lines.map((r) => r.productId).toSet();

    if (answered.length != counted.length || !answered.containsAll(counted.keys)) {
      return CountCommit.failed(Lang.get('screens.stock_take.commit_failed'));
    }

    // Every balance this count touched is now stale in BOTH caches, including for the stock list the
    // user goes back to. The shelf is refetched rather than dropped, because the screen that asked
    // for it is still on screen and still rendering from it.
    await Future.wait(<Future<void>>[load(), loadShelf(locationId, force: true)]);

    return CountCommit.landed(lines);
  }

  /// The query string for one browse request.
  String _query({String? cursor}) => _filter.toQueryString(
    extra: <String, Object?>{
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

  static CountOutcome? _outcome(String? raw) => switch (raw) {
    'written' => CountOutcome.written,
    'matched' => CountOutcome.matched,
    'needs_date' => CountOutcome.needsDate,
    'serial_tracked' => CountOutcome.serialTracked,
    _ => null,
  };

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
