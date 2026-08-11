import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart' show MSEmptyState, MSInput, MSPageScaffold;

import '../../ui/components/location_row/location_row.dart';
import '../../ui/components/product_row/product_row.dart';
import '../../ui/components/section_card/section_card.dart';
import 'locations/location_fixtures.dart';
import 'locations/location_index_view.dart' show LocationNode;
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
  /// Creates the [SearchView].
  const SearchView({super.key});

  @override
  State<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<SearchView> {
  static const IconData _searchIcon = Icons.search_outlined;
  static const IconData _noMatchIcon = Icons.search_off_outlined;

  String _query = '';

  String get _needle => _query.trim().toLowerCase();

  bool get _hasQuery => _needle.isNotEmpty;

  /// Products whose name, brand or SKU contains the query.
  ///
  /// SKU is included because a user who has one uses it, and a code is exactly the kind of thing
  /// somebody types in full rather than browses for.
  List<ProductListItem> get _products {
    if (!_hasQuery) return const <ProductListItem>[];
    return productFixtures.where((ProductListItem p) {
      return p.name.toLowerCase().contains(_needle) ||
          (p.brand?.toLowerCase().contains(_needle) ?? false) ||
          (p.sku?.toLowerCase().contains(_needle) ?? false) ||
          (p.categoryLabel?.toLowerCase().contains(_needle) ?? false);
    }).toList();
  }

  /// Locations whose own name or ancestor path contains the query.
  ///
  /// The PATH is searched, not only the name, so "Kiler raf" finds `Kiler › Raf 1`. A user
  /// describes where something is by the route to it, not by the leaf's name alone.
  List<LocationNode> get _locations {
    if (!_hasQuery) return const <LocationNode>[];
    return locationTree
        .where((LocationNode n) => n.path.toLowerCase().contains(_needle))
        .toList();
  }

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
      onChanged: (String next) => setState(() => _query = next),
    );
  }

  Widget _buildProducts(List<ProductListItem> products) {
    return SectionCard(
      label: Lang.get('screens.search.products_group'),
      count: Lang.get('screens.products.product_count', {'count': products.length}),
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
            onTap: () => MagicRoute.to('/urunler/${item.id ?? Uri.encodeComponent(item.name)}'),
          ),
      ],
    );
  }

  Widget _buildLocations(List<LocationNode> locations) {
    return SectionCard(
      label: Lang.get('screens.search.locations_group'),
      count: Lang.get('screens.location.location_count', {'count': locations.length}),
      children: [
        for (final LocationNode node in locations)
          LocationRow(
            // The full path, and depth zero: a result list has no tree above it, so an indent
            // would be measured against something that is not on screen.
            name: node.path,
            depth: 0,
            productCount: node.productCount,
            itemSummary: node.summary,
            icon: node.icon,
            onTap: () => MagicRoute.to('/konumlar/${Uri.encodeComponent(node.path)}'),
          ),
      ],
    );
  }

  /// Where things are kept, offered before anything is typed.
  Widget _buildPlaces() {
    final List<LocationNode> roots = locationTree.where((LocationNode n) => n.depth == 0).toList();

    return SectionCard(
      label: Lang.get('screens.search.places_group'),
      count: Lang.get('screens.location.location_count', {'count': roots.length}),
      children: [
        for (final LocationNode node in roots)
          LocationRow(
            name: node.name,
            depth: 0,
            productCount: node.productCount,
            itemSummary: node.summary,
            icon: node.icon,
            onTap: () => MagicRoute.to('/konumlar/${Uri.encodeComponent(node.path)}'),
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
            title: Lang.get('screens.search.empty_title', {'query': _query.trim()}),
            description: Lang.get('screens.search.empty_description'),
          ),
        ),
      ],
    );
  }
}
