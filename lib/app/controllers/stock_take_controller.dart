import 'package:magic/magic.dart';

import '../../resources/views/products/count_line.dart';
import '../../resources/views/products/product_filter_sheet.dart';
import '../../resources/views/products/product_fixtures.dart';
import '../models/product_filter.dart';
import '../support/mapped_or_null.dart';
import '../support/scan_outcome.dart';
import 'product_controller.dart';

/// One shelf being counted, and the commit that turns what was found into ledger entries.
///
/// ### Why this is its own controller
///
/// It used to live inside [ProductController] as a second cache, and that was defensible while a
/// shelf was one thing: a list of rows, fetched once. It stopped being defensible when the shelf
/// gained its own query, its own order, its own cursor, its own total and its own failure state.
/// That is a second state machine, and two state machines in one class share nothing but a file:
/// every field has to be read twice to know which list it belongs to.
///
/// The two are genuinely different questions. [ProductController] answers "what is in the catalogue,
/// narrowed how the user asked". This answers "what does the record say is on THIS shelf", which is
/// scoped to one location by definition, ordered for walking rather than for browsing, and thrown
/// away when the user moves to the next shelf.
///
/// ### One shelf at a time, on purpose
///
/// A map keyed by location would cache every shelf visited, which sounds free and is not: a count is
/// checked against what the record says RIGHT NOW, and a shelf cached ten minutes ago is a stale
/// expected figure the user would count against. Switching location drops the previous shelf.
///
/// ### Pagination is safe here, and it is worth saying why
///
/// A paginated count sheet cannot commit a partial count, because an uncounted row writes NOTHING
/// (D58, D59). A row the user never scrolled to is a row they never typed into, and the commit only
/// sends what was typed. That is the opposite of the failure this screen had before pagination,
/// where the sheet was built from the browse list's page and LOOKED complete while being short.
/// [total] is what keeps it honest: the header states the shelf's real size, not the loaded count.
class StockTakeController extends MagicController with MagicStateMixin<List<ProductListItem>> {
  /// How many rows a shelf page asks for.
  ///
  /// Larger than the browse list's thirty, because a count is a walk rather than a browse: the user
  /// is going through every row, so a bigger page means fewer pauses.
  static const int _pageSize = 50;

  /// The shared instance, keyed by type.
  static StockTakeController get instance => Magic.findOrPut(StockTakeController.new);

  String _locationId = '';

  String _query = '';

  ProductSort _sort = ProductSort.name;

  String? _cursor;

  int _total = 0;

  bool _loadingMore = false;

  bool _failed = false;

  int _requestId = 0;

  /// Which shelf is being counted, or empty before one is chosen.
  String get locationId => _locationId;

  /// The rows loaded so far, already narrowed by [query].
  List<ProductListItem> get rows => rxState ?? const <ProductListItem>[];

  /// The free text narrowing the shelf.
  String get query => _query;

  /// The order the rows are in.
  ProductSort get sort => _sort;

  /// How many products the record says are on this shelf, matching [query].
  ///
  /// **The header counts against this rather than against the loaded rows.** With a page of fifty
  /// and a shelf of a thousand, `0 / 50 counted` would tell a user they were nearly done fifty rows
  /// in. The server answers the real figure whether or not the client has scrolled to it.
  int get total => _total;

  /// Whether another page exists.
  bool get hasMore => _cursor != null;

  /// Whether that next page is in flight.
  bool get loadingMore => _loadingMore;

  /// Whether the last fetch for this shelf failed.
  bool get failed => _failed;

  /// Opens a shelf, dropping whatever the previous one held.
  ///
  /// The typed counts are NOT this controller's to clear: the screen owns them, because they are
  /// the user's input rather than fetched state. It clears them on the same gesture, for the reason
  /// its own chip handler records (a number entered for one shelf must never commit against another).
  Future<void> open(String locationId, {bool force = false}) async {
    if (locationId.isEmpty) return;
    if (!force && locationId == _locationId && rxState != null) return;

    _locationId = locationId;
    _query = '';
    _cursor = null;

    // **Reset the total and go back to loading, or the header lies for a moment.** The docblock says
    // this drops what the previous shelf held, and it did not drop these two: with rows already on
    // screen `_load` skips `setLoading`, so the new shelf rendered the OLD one's rows and the OLD
    // one's total until the response landed. On a count screen that moment reads as `0 of 25` for a
    // shelf holding four.
    _total = 0;
    setLoading();

    await _load();
  }

  /// Narrows the shelf by free text, from the first page.
  Future<void> search(String query) async {
    if (query == _query) return;

    _query = query;

    await _load();
  }

  /// Reorders the shelf, from the first page.
  ///
  /// The cursor is dropped for the same reason a filter change drops it: a cursor is a position in
  /// ONE ordering, so continuing it under another asks the server to resume a list it never made.
  Future<void> reorder(ProductSort sort) async {
    if (sort == _sort) return;

    _sort = sort;

    await _load();
  }

  /// Refetches the current shelf, keeping the query and the order.
  Future<void> refresh() => _load();

  /// Appends the next page of the shelf.
  Future<void> loadMore() async {
    if (_cursor == null || _loadingMore) return;

    final int request = _requestId;
    final String cursor = _cursor!;

    _loadingMore = true;
    refreshUI();

    final dynamic response = await Http.get('/products?${_queryString(cursor: cursor)}');

    // Cleared before the stale return, not after: leaving it set would refuse every later page for
    // the rest of the session, which is the defect `ProductController.loadMore` carried and the
    // reason this one was written the other way round from the start.
    _loadingMore = false;

    if (request != _requestId) return;

    if (!response.successful) {
      // The rows already on screen stay. A failed next page is not a failed count.
      refreshUI();

      return;
    }

    final List<ProductListItem>? more = mappedOrNull(
      () => _map(response['data']),
      describing: 'a shelf page',
    );

    // The rows already on screen stay, for the same reason a failed request leaves them.
    if (more == null) {
      refreshUI();

      return;
    }

    _cursor = _cursorOf(response);

    setSuccess(<ProductListItem>[...rows, ...more]);
  }

  /// Commits a physical count of this shelf, then refetches what it changed (D59).
  ///
  /// ### Why the commit lives here rather than on the products list
  ///
  /// Because this is the cache it falsifies. It also falsifies the browse list, so that one is
  /// reloaded too, but through its own controller rather than by reaching into its state: the two
  /// own their own fetching, and a commit is one thing that happens to invalidate both.
  ///
  /// The counts are keyed by product id, not by name. Two products can share a name, and with real
  /// data one pair does, so keying by name would let a count of one write itself onto the other.
  ///
  /// Asks the server what a scanned code is, and classifies the answer against this shelf.
  ///
  /// **A dedicated endpoint rather than the search, because a miss has two meanings.** Narrowing the
  /// list by the code would scope the answer to this location, so a product the tenant owns but keeps
  /// elsewhere and a product nobody has ever owned would both come back empty, and those call for
  /// opposite responses. `by-barcode` answers about the product alone.
  ///
  /// A 404 is an answer rather than a failure: it means the tenant has no product carrying this code,
  /// which is [ScanVerdict.unknown]. Anything else that goes wrong is a failure and says so, because
  /// a network error silently reported as "unknown product" would send the user to create a product
  /// they already have.
  Future<ScanOutcome?> resolveScan(String code, {String? symbology}) async {
    final Map<String, String> params = <String, String>{
      'code': code,
      if (symbology != null && symbology.isNotEmpty) 'symbology': symbology,
    };

    final String query = params.entries
        .map((MapEntry<String, String> e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');

    final dynamic response = await Http.get('/products/by-barcode?$query');

    if (response.statusCode == 404) {
      return ScanOutcome.of(code: code, product: null, shelfId: _locationId);
    }

    // Null rather than an outcome, so the caller can tell "the server says no such product" from
    // "the question never got an answer". Reporting the second as the first is how a user ends up
    // creating a duplicate of a product they already own.
    if (!response.successful) {
      return null;
    }

    final ProductListItem? product = mappedOrNull(
      () => ProductListItem.fromApi(
        response['data'] as Map<String, dynamic>,
        locationLabels: ProductController.instance.locationLabels,
        today: DateTime.now(),
      ),
      describing: 'a scanned product',
    );

    // Null for the same reason a failed request answers null: the caller has to be able to tell "no
    // such product" from "the answer was unreadable", because only the first means create one.
    if (product == null) return null;

    return ScanOutcome.of(code: code, product: product, shelfId: _locationId);
  }

  /// A per-line refusal is not a failure. The endpoint commits every writable line and names the
  /// rest, so this returns the whole answer and lets the screen decide what is still unfinished.
  Future<CountCommit> commit(String locationId, Map<String, num> counted) async {
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

      // An outcome this build does not know means the server answered in a vocabulary added after
      // it. Failing the whole commit is the honest reading: mapping the unknown onto `matched` would
      // tell the user a row is finished, and onto `needsDate` would send them to fix a fine one.
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

    // **A 200 that does not answer every line is a failure, not an empty success.** A response whose
    // `data.lines` was missing or short parses into a list with no unfinished rows, so the screen
    // would show a success and navigate away from a shelf it had not committed. On a ledger that is
    // the worst shape available: the user believes the count landed and nothing says otherwise.
    //
    // Compared by SET rather than by count, so a response echoing one product twice and omitting
    // another cannot pass by arithmetic.
    final Set<String> answered = lines.map((r) => r.productId).toSet();

    if (answered.length != counted.length || !answered.containsAll(counted.keys)) {
      return CountCommit.failed(Lang.get('screens.stock_take.commit_failed'));
    }

    // Both caches are stale now. The browse list is reloaded through its own controller rather than
    // by touching its fields, so each one stays the only thing that fetches its own rows.
    await Future.wait(<Future<void>>[refresh(), ProductController.instance.load()]);

    return CountCommit.landed(lines);
  }

  /// Fetches the first page of the current shelf.
  Future<void> _load() async {
    final int request = ++_requestId;

    _failed = false;
    _cursor = null;
    _loadingMore = false;

    // Skeletons only when there is nothing to show, so narrowing a shelf the user is reading does
    // not blank it out and redraw.
    if (rxState == null) setLoading();

    final dynamic response = await Http.get('/products?${_queryString()}');

    if (request != _requestId) return;

    if (!response.successful) {
      _failed = true;
      setError(Lang.get('screens.products.load_failed'));

      return;
    }

    final List<ProductListItem>? fetched = mappedOrNull(
      () => _map(response['data']),
      describing: 'a shelf payload',
    );

    // A payload this client cannot read is a failed load, not a shelf that waits forever.
    if (fetched == null) {
      _failed = true;
      setError(Lang.get('screens.products.load_failed'));

      return;
    }

    _cursor = _cursorOf(response);
    _total = _totalOf(response) ?? fetched.length;

    setSuccess(fetched);
  }

  /// The query string for one shelf request.
  ///
  /// Built from the same `ProductFilter` the browse list sends, because a shelf IS a filtered
  /// product list: one location, optionally narrowed by text. Reusing it means the count screen
  /// cannot drift from the endpoint's own vocabulary.
  String _queryString({String? cursor}) => ProductFilter(
    query: _query,
    locationIds: <String>{_locationId},
  ).toQueryString(
    extra: <String, Object?>{
      'sort': ?_sort.wire,
      'per_page': _pageSize,
      'cursor': ?cursor,
    },
  );

  List<ProductListItem> _map(Object? data) {
    // ONE reference date for the page, so rows mapped across midnight cannot disagree by a day.
    final DateTime today = DateTime.now();

    return <ProductListItem>[
      for (final Map<String, dynamic> row in _rows(data))
        ProductListItem.fromApi(
          row,
          locationLabels: ProductController.instance.locationLabels,
          today: today,
        ),
    ];
  }

  String? _cursorOf(dynamic response) {
    final dynamic meta = response['meta'];
    final dynamic cursor = meta is Map<dynamic, dynamic> ? meta['next_cursor'] : null;

    return cursor is String && cursor.isNotEmpty ? cursor : null;
  }

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

  List<Map<String, dynamic>> _rows(Object? data) => <Map<String, dynamic>>[
    if (data is List<dynamic>)
      for (final dynamic row in data)
        if (row is Map<dynamic, dynamic>) Map<String, dynamic>.from(row),
  ];
}

/// The locations a count can be scoped to, re-exported so the screen has one import.
typedef ShelfOption = FilterOption;
