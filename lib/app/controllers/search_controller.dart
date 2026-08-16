import 'dart:async';

import 'package:magic/magic.dart';

import '../../resources/views/products/product_fixtures.dart';
import '../models/location_node.dart';
import '../support/mapped_or_null.dart';
import 'location_controller.dart';

/// One box, two kinds of answer, from `api/v1/search`.
///
/// ### Debounced, because a search box fires per keystroke
///
/// 300ms after the last one. Shorter and typing "buzdolabı" is nine requests; longer and the
/// results feel like they are catching up rather than following along. The same figure the icon
/// picker uses, which is the other search field in this app.
///
/// ### A stale answer is dropped rather than shown
///
/// Each search carries a sequence number and a response whose number is not the current one is
/// discarded. Without it a slow request for "bu" lands after a fast one for "buzdolabı" and the
/// screen shows results for text the user has already typed past.
class SearchController extends MagicController with MagicStateMixin<SearchResults> {
  /// The shared instance, keyed by type.
  static SearchController get instance => Magic.findOrPut(SearchController.new);

  /// How long to wait after the last keystroke.
  static const Duration _debounce = Duration(milliseconds: 300);

  Timer? _timer;

  int _sequence = 0;

  String _query = '';

  /// What the field currently holds, trimmed.
  String get query => _query;

  /// Whether there is anything to search for.
  bool get hasQuery => _query.isNotEmpty;

  /// What was found, or empty before the first answer.
  SearchResults get results => rxState ?? const SearchResults.empty();

  /// Whether the results on screen answer the text in the field.
  ///
  /// **Not the same as "not loading".** Between a keystroke and the debounce firing, nothing is in
  /// flight and the held results belong to the PREVIOUS query, so a screen keyed on the loading flag
  /// alone would show "no match" for text nobody has searched yet.
  bool get isSettled => _settledFor == _query;

  String? _settledFor;

  /// Called on every keystroke.
  void search(String next) {
    _query = next.trim();

    _timer?.cancel();

    if (_query.isEmpty) {
      // Nothing to ask, and the screen has its own "start typing" state for it. Cleared rather than
      // left, or clearing the field would leave the last answer under it.
      _settledFor = '';
      setSuccess(const SearchResults.empty());

      return;
    }

    _timer = Timer(_debounce, _run);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _run() async {
    final int sequence = ++_sequence;
    final String query = _query;

    setLoading();

    final dynamic response = await Http.get('/search?q=${Uri.encodeQueryComponent(query)}');

    // A newer search started while this one was in flight, so this answer is stale by definition.
    if (sequence != _sequence) return;

    if (!response.successful) {
      setError(response.message ?? Lang.get('screens.search.load_failed'));

      return;
    }

    // The location half arrives as `LocationResource`, which the tree already knows how to read, so
    // the summary line is the same sentence the tree shows for the same place.
    final SearchResults? found = mappedOrNull<SearchResults?>(
      () {
        final Object? data = response['data'];

        if (data is! Map<String, dynamic>) return null;

        final Map<String, String> labels = <String, String>{
          for (final LocationNode node in LocationController.instance.nodes)
            if (node.id != null) node.id!: node.path,
        };

        return SearchResults(
          products: (data['products'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<Map<String, dynamic>>()
              .map((Map<String, dynamic> row) =>
                  ProductListItem.fromApi(row, locationLabels: labels))
              .toList(),
          locations: (data['locations'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<Map<String, dynamic>>()
              .map((Map<String, dynamic> row) =>
                  LocationNode.fromApi(row, summarise: (int _) => ''))
              .whereType<LocationNode>()
              .toList(),
        );
      },
      describing: 'the search results',
    );

    if (found == null) {
      setError(Lang.get('screens.search.load_failed'));

      return;
    }

    _settledFor = query;

    setSuccess(found);
  }
}

/// What one search found.
class SearchResults {
  /// Matching products.
  final List<ProductListItem> products;

  /// Matching locations.
  final List<LocationNode> locations;

  /// Creates a [SearchResults].
  const SearchResults({required this.products, required this.locations});

  /// Nothing found, which is also the state before anything has been asked.
  const SearchResults.empty()
    : products = const <ProductListItem>[],
      locations = const <LocationNode>[];

  /// Whether both halves are empty.
  bool get isEmpty => products.isEmpty && locations.isEmpty;
}
