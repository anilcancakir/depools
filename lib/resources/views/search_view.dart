import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart' show MSEmptyState, MSInput, MSPageScaffold;

import '../../../app/support/plural.dart';
import '../../app/models/location_node.dart';
import '../../ui/components/location_row/location_row.dart';
import '../../ui/components/product_row/product_row.dart';
import '../../ui/components/section_card/section_card.dart';
import '../../app/controllers/location_controller.dart';
import '../../app/controllers/search_controller.dart';
import 'products/product_fixtures.dart';

/// Finding a thing, wherever it is, whatever kind of thing it is.
///
/// ### Why one search rather than a field per list
///
/// Four search inputs existed in the app and every one of them was dead, each scoped to the list it
/// sat on. That cannot satisfy what `iterations.md` asks for in v1, which is search over products,
/// locations and categories: a location cannot be found from the product list, and a user who
/// remembers "it is in the drawer" and not which drawer has nowhere to type that.
///
/// It is also the surface `CaptureVerb.inventory` exists for. D66 says the user picks which capture
/// verb leads on the overview, and one of the two is "look it up". That promise needs a place where
/// looking things up actually happens.
///
/// ### Results are grouped by kind, not interleaved by score
///
/// A relevance-ranked mixed list is the obvious implementation and the wrong interface here. The
/// two kinds answer different questions ("how much milk do I have" versus "what is in Raf 2") and a
/// product row and a location row carry different information, so interleaving them makes the user
/// re-read the shape of every row to work out what they are looking at. Grouped, the eye goes to
/// the section it wants.
///
/// Products lead because they are what most searches are for. The group headers carry counts, so a
/// search that matched nothing in one kind says so by showing that group's absence rather than by
/// silently omitting it.
///
/// ### The empty query is not an empty screen
///
/// Before anything is typed, the screen offers what a user most often wants: the places they keep
/// things. That makes the screen useful on arrival instead of being a blank box, which is the same
/// reasoning that keeps the assistant's fresh state from being an empty transcript.
@immutable
class SearchView extends StatefulWidget {
  /// The tree offered before anything is typed, or null to read [LocationController].
  ///
  /// The preview passes the fixture, which is how the catalog renders this screen with no server.
  /// The RESULTS have no such escape and do not need one: a preview of a search that has not been
  /// typed into shows the places card, which is exactly this list.
  final List<LocationNode>? places;

  /// Creates the [SearchView].
  const SearchView({super.key, this.places});

  @override
  State<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<SearchView> {
  static const IconData _searchIcon = Icons.search_outlined;
  static const IconData _noMatchIcon = Icons.search_off_outlined;

  SearchController? _search;
  LocationController? _tree;

  @override
  void initState() {
    super.initState();

    final SearchController search = SearchController.instance..addListener(_onChanged);

    if (!search.initialized) search.onInit();

    _search = search;

    if (widget.places != null) return;

    final LocationController tree = LocationController.instance..addListener(_onChanged);

    if (!tree.initialized) tree.onInit();

    _tree = tree;
  }

  @override
  void dispose() {
    _search?.removeListener(_onChanged);
    _tree?.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  bool get _hasQuery => _search?.hasQuery ?? false;

  /// Matching products, from the server.
  List<ProductListItem> get _products => _search?.results.products ?? const <ProductListItem>[];

  /// Matching locations, likewise.
  List<LocationNode> get _locations => _search?.results.locations ?? const <LocationNode>[];

  /// Every location the app knows about, for the places card.
  List<LocationNode> get _places => widget.places ?? _tree?.nodes ?? const <LocationNode>[];

  @override
  Widget build(BuildContext context) {
    final List<ProductListItem> products = _products;
    final List<LocationNode> locations = _locations;
    final bool nothing = _hasQuery && products.isEmpty && locations.isEmpty;

    return MSPageScaffold(
      title: Lang.get('screens.search.title'),
      subtitle: Lang.get('screens.search.subtitle'),
      children: [
        _buildField(),
        if (!_hasQuery)
          _buildPlaces()
        else if (nothing)
          _buildNoMatch()
        else ...[
          if (products.isNotEmpty) _buildProducts(products),
          if (locations.isNotEmpty) _buildLocations(locations),
        ],
      ],
    );
  }

  /// The one field, on the page rather than on a card.
  ///
  /// The input tone is correct here for the same reason it is on the stock list: this sits on the
  /// PAGE surface, where `bg-surface-container-high` reads as a well rather than as a disabled
  /// control.
  Widget _buildField() {
    return MSInput(
      className: 'h-11 bg-surface-container-high',
      placeholder: Lang.get('screens.search.placeholder'),
      prefix: const WIcon(_searchIcon, className: 'size-4 text-fg-muted'),
      // Debounced in the controller rather than here, because the wait belongs with the request:
      // a field that debounced its own `setState` would also delay the letters appearing.
      onChanged: (String next) => _search?.search(next),
    );
  }

  Widget _buildProducts(List<ProductListItem> products) {
    return SectionCard(
      label: Lang.get('screens.search.products_group'),
      count: plural('screens.products.product_count', products.length, {'count': products.length}),
      children: [
        for (final ProductListItem item in products)
          ProductRow(
            name: item.name,
            // The location joins the meta line here, unlike on a location's own screen: a search
            // result has no ambient context, so where the thing is is half the answer.
            meta: item.meta,
            amount: item.amount,
            formatted: item.formatted,
            unit: item.unit,
            expiryLabel: item.expiryLabel,
            daysUntilExpiry: item.daysUntilExpiry,
            parLevel: item.parLevel,
            // The server id when there is one. Every tap on a product now reaches an endpoint, so a
            // route carrying a NAME 404s; the fallback keeps the fixture-only previews navigating.
            onTap: () => MagicRoute.to('/products/${item.id ?? Uri.encodeComponent(item.name)}'),
          ),
      ],
    );
  }

  Widget _buildLocations(List<LocationNode> locations) {
    return SectionCard(
      label: Lang.get('screens.search.locations_group'),
      count: plural(
        'screens.location.location_count',
        locations.length,
        {'count': locations.length},
      ),
      children: [
        for (final LocationNode node in locations)
          LocationRow(
            // The full path, and depth zero: a result list has no tree above it, so an indent
            // would be measured against something that is not on screen.
            name: node.path,
            depth: 0,
            productCount: node.productCount,
            itemSummary: node.summary.isEmpty ? null : node.summary,
            icon: node.icon,
            // The id, like every other row that opens a location: the path was the fixture-era
            // stand-in and the detail screen cannot look a node up by it.
            onTap: node.id == null ? null : () => MagicRoute.to('/locations/${node.id}'),
          ),
      ],
    );
  }

  /// Where things are kept, offered before anything is typed.
  Widget _buildPlaces() {
    final List<LocationNode> roots = _places.where((LocationNode n) => n.depth == 0).toList();

    return SectionCard(
      label: Lang.get('screens.search.places_group'),
      count: plural('screens.location.location_count', roots.length, {'count': roots.length}),
      children: [
        for (final LocationNode node in roots)
          LocationRow(
            name: node.name,
            depth: 0,
            productCount: node.productCount,
            itemSummary: node.summary.isEmpty ? null : node.summary,
            icon: node.icon,
            // The id, like every other row that opens a location: the path was the fixture-era
            // stand-in and the detail screen cannot look a node up by it.
            onTap: node.id == null ? null : () => MagicRoute.to('/locations/${node.id}'),
          ),
      ],
    );
  }

  Widget _buildNoMatch() {
    return WDiv(
      className: 'flex flex-col gap-3 p-4 rounded-lg bg-surface-container',
      children: [
        WDiv(
          className: 'w-full',
          child: MSEmptyState(
            icon: _noMatchIcon,
            title: Lang.get('screens.search.empty_title', {'query': _search?.query ?? ''}),
            description: Lang.get('screens.search.empty_description'),
          ),
        ),
      ],
    );
  }
}
