import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart' show ButtonIntent, MSButton, MSEmptyState;

import '../../../ui/components/location_row/location_row.dart';
import '../../../ui/components/product_row/product_row.dart';
import '../../../ui/components/section_card/section_card.dart';
import '../../../ui/layouts/app_page_scaffold.dart';
import '../products/product_fixtures.dart';
import 'location_fixtures.dart';
import 'location_index_view.dart' show LocationNode;

/// What is in one place, including everything nested under it.
///
/// ### Why this screen has to exist
///
/// `inventory-core.md` lists it as one of seven things the user does: "sees, for any location,
/// everything in it including nested locations". Until now the location tree's rows had nowhere to
/// go, so the hierarchy was browsable and not inspectable: a user could see that "Kiler" holds four
/// products and could not find out which four.
///
/// ### Here versus below, kept apart
///
/// The two questions a person standing in front of a shelf asks are different. "What is ON this
/// shelf" is what they can reach; "what is in the boxes on it" is a second trip. Folding both into
/// one list would make a location with three sub-locations read as if it physically contained
/// forty items, which is how a user stops trusting a count.
///
/// So: products held directly here first, then the child locations with their own totals. The
/// header's subtitle carries the rolled-up figure, because that IS the number the tree showed and
/// the two must agree.
///
/// ### The empty state is not a failure
///
/// An empty shelf is the normal state of a shelf you are about to fill, and `location-assignment.md`
/// makes finding one a first-class task (the tree's `Boş` filter exists for it). So an empty
/// location offers stock-in rather than apologising.
@immutable
class LocationShowView extends StatelessWidget {
  static const IconData _emptyIcon = Icons.inbox_outlined;
  static const IconData _addIcon = Icons.add_outlined;

  /// Which node this is. Fixture-backed for now, like every other screen.
  final LocationNode node;

  /// Creates the [LocationShowView] for a location holding stock.
  ///
  /// `Kiler › Raf 1` rather than `Kiler`, because Kiler is a pure container in the fixtures: it
  /// holds four products and every one of them is in a shelf inside it. That renders only one of
  /// this screen's two sections, and the whole design decision here is that the two are separate.
  LocationShowView({super.key})
    : node = locationTree.firstWhere((LocationNode n) => n.path == 'Kiler › Raf 1');

  /// Creates the view for a place that holds nothing, which is its own reviewable state.
  LocationShowView.empty({super.key})
    : node = locationTree.firstWhere((LocationNode n) => n.productCount == 0);

  /// The direct children of this node, one level down only.
  List<LocationNode> get _children => locationTree
      .where((LocationNode n) => n.depth == node.depth + 1 && n.path.startsWith('${node.path} ›'))
      .toList();

  /// The products this fixture places directly here.
  List<ProductListItem> get _held =>
      productFixtures.where((ProductListItem p) => p.locationSummary == node.path).toList();

  @override
  Widget build(BuildContext context) {
    final List<LocationNode> children = _children;
    final List<ProductListItem> held = _held;
    final bool isEmpty = children.isEmpty && held.isEmpty;

    return AppPageScaffold(
      title: node.name,
      // The path rather than the name alone: "Raf 2" means nothing without the room it is in, and
      // this is the one screen where the user arrived by tapping a row that showed the name only.
      // **The rolled-up count is derived here rather than read off the tree node.** The tree
      // fixture and the product fixture are two files and they disagreed: the node said one
      // product, the section below said two. A header that contradicts the list under it is worse
      // than no header, so both come from the same count.
      subtitle: Lang.get('screens.location.subtitle', {
        'path': node.path,
        'products': held.length + children.fold<int>(0, (int a, LocationNode c) => a + c.productCount),
      }),
      backLabel: Lang.get('screens.location.back'),
      backFallback: '/konumlar',
      actions: [
        MSButton(
          onPressed: () => MagicRoute.to('/konumlar/yeni'),
          className: 'min-h-11 min-w-11 justify-center',
          semanticLabel: Lang.get('screens.location.add_child'),
          child: const WIcon(_addIcon),
        ),
      ],
      footer: _buildFooter(),
      children: [
        if (isEmpty) _buildEmpty() else ...[
          if (held.isNotEmpty) _buildHeld(held),
          if (children.isNotEmpty) _buildChildren(children),
        ],
      ],
    );
  }

  /// What is physically on this shelf.
  Widget _buildHeld(List<ProductListItem> held) {
    return SectionCard(
      label: Lang.get('screens.location.here_group'),
      count: Lang.get('screens.location.product_count', {'count': held.length}),
      children: [
        for (final ProductListItem item in held)
          ProductRow(
            name: item.name,
            // The brand only. `item.meta` folds in the location, and the location is the whole
            // screen here: repeating it on every row is the ambient-context mistake
            // `LocationRow`'s own-name rule already avoids.
            meta: item.brand,
            amount: item.amount,
            formatted: item.formatted,
            unit: item.unit,
            daysUntilExpiry: item.daysUntilExpiry,
            expiryLabel: item.expiryLabel,
            parLevel: item.parLevel,
            onTap: () {},
          ),
      ],
    );
  }

  /// The places inside this one, with their own totals.
  Widget _buildChildren(List<LocationNode> children) {
    return SectionCard(
      label: Lang.get('screens.location.children_group'),
      count: Lang.get('screens.location.location_count', {'count': children.length}),
      children: [
        for (final LocationNode child in children)
          LocationRow(
            name: child.name,
            // Depth 0 because the parent is the screen: an indent here would be measured from a
            // tree that is not on screen, which is the same trap the filtered index avoids.
            depth: 0,
            productCount: child.productCount,
            itemSummary: child.summary,
            icon: child.icon,
            onTap: () {},
          ),
      ],
    );
  }

  /// A place that holds nothing, which is what somebody looking for space wants to find.
  Widget _buildEmpty() {
    return WDiv(
      className: 'flex flex-col gap-3 p-4 rounded-lg bg-surface-container',
      children: [
        WDiv(
          className: 'w-full',
          child: MSEmptyState(
            icon: _emptyIcon,
            title: Lang.get('screens.location.empty_title'),
            description: Lang.get('screens.location.empty_description'),
          ),
        ),
      ],
    );
  }

  /// Putting something here is the action this screen exists to make easy.
  Widget _buildFooter() {
    return MSButton(
      onPressed: () {},
      intent: ButtonIntent.primary,
      fullWidth: true,
      className: 'justify-center',
      child: WText(Lang.get('screens.location.stock_in')),
    );
  }
}
