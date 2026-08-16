import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart' show ButtonIntent, ConfirmDialogVariant, MSButton, MSEmptyState, MagicStarterConfirmDialog;

import '../../../app/models/location_node.dart';
import '../../../ui/components/location_row/location_row.dart';
import '../../../ui/components/product_row/product_row.dart';
import '../../../ui/components/section_card/section_card.dart';
import '../../../ui/layouts/app_page_scaffold.dart';
import '../../../app/controllers/location_controller.dart';
import '../../../app/controllers/location_detail_controller.dart';
import '../../../app/support/plural.dart';
import '../products/product_fixtures.dart';

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
class LocationShowView extends StatefulWidget {
  /// The location's id from the route, or null in the preview catalog.
  final String? id;

  /// The node and its siblings, supplied by the caller, which is how the preview stays offline.
  ///
  /// Null means "read [LocationController]". The whole TREE rather than one node, because this
  /// screen renders a node's children too and they are rows of the same list.
  final List<LocationNode>? nodes;

  /// The products held here, supplied by the caller for the same reason.
  final List<ProductListItem>? held;

  /// Which node the preview shows, when the caller supplied a tree instead of an id.
  final String? previewPath;

  /// Creates the [LocationShowView] for the location at [id].
  const LocationShowView({super.key, this.id, this.nodes, this.held, this.previewPath});

  /// Creates the view for a location holding stock, from the fixtures.
  ///
  /// `Kiler › Raf 1` rather than `Kiler`, because Kiler is a pure container in the fixtures: it
  /// holds four products and every one of them is in a shelf inside it. That renders only one of
  /// this screen's two sections, and the whole design decision here is that the two are separate.
  const LocationShowView.preview({super.key, this.nodes, this.held})
    : id = null,
      previewPath = 'Kiler › Raf 1';

  /// Creates the view for a place that holds nothing, which is its own reviewable state.
  const LocationShowView.empty({super.key, this.nodes})
    : id = null,
      held = const <ProductListItem>[],
      previewPath = 'Depo › Raf B';

  @override
  State<LocationShowView> createState() => _LocationShowViewState();
}

class _LocationShowViewState extends State<LocationShowView> {
  static const IconData _emptyIcon = Icons.inbox_outlined;
  static const IconData _addIcon = Icons.add_outlined;

  LocationController? _tree;
  LocationDetailController? _detail;

  @override
  void initState() {
    super.initState();

    if (widget.id == null) return;

    final LocationController tree = LocationController.instance
      ..addListener(_onChanged);

    // Same `onInit` contract every wired screen here needs; the tree is what this screen's own node
    // comes from, so without it the header would have no name to show.
    if (!tree.initialized) tree.onInit();

    final LocationDetailController detail = LocationDetailController.instance
      ..addListener(_onChanged);

    if (!detail.initialized) detail.onInit();

    _tree = tree;
    _detail = detail;

    detail.load(widget.id!);
  }

  @override
  void dispose() {
    _tree?.removeListener(_onChanged);
    _detail?.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  /// Every location the app knows about, whatever the source.
  List<LocationNode> get _all => widget.nodes ?? _tree?.nodes ?? const <LocationNode>[];

  /// The node this screen is about, or null while the tree is still arriving.
  ///
  /// **By id from the route, or by path in the preview**, because a fixture has no id to route to
  /// and the catalog still has to render a specific node rather than whichever one is first.
  LocationNode? get _node {
    for (final LocationNode candidate in _all) {
      if (widget.id != null ? candidate.id == widget.id : candidate.path == widget.previewPath) {
        return candidate;
      }
    }

    return null;
  }

  /// The direct children of this node, one level down only.
  List<LocationNode> _childrenOf(LocationNode node) => _all
      .where((LocationNode n) => n.depth == node.depth + 1 && n.path.startsWith('${node.path} \u203a'))
      .toList();

  /// Everything under this node, at any depth, for the rolled-up figure in the header.
  ///
  /// Read off the tree rather than asked for: the subtitle has to agree with what the tree row
  /// showed, and both are now the same numbers from the same payload.
  int _subtreeCount(LocationNode node) => _all
      .where((LocationNode n) => n.path == node.path || n.path.startsWith('${node.path} \u203a'))
      .fold<int>(0, (int sum, LocationNode n) => sum + n.productCount);

  @override
  Widget build(BuildContext context) {
    final LocationNode? node = _node;

    // Nothing to draw until the tree arrives. The scaffold needs a name for its title, and inventing
    // one would put a placeholder in the one place a user checks they opened the right shelf.
    if (node == null) return const SizedBox.shrink();

    final List<LocationNode> children = _childrenOf(node);
    final List<ProductListItem> held = widget.held ?? _detail?.held ?? const <ProductListItem>[];

    // **An empty shelf is an ANSWER, and it cannot be shown before there is one.** The empty state
    // offers stock-in, so rendering it mid-fetch would invite a user to fill a shelf that is
    // already full.
    final bool hasAnswer =
        widget.held != null || (widget.id != null && (_detail?.loadedFor(widget.id!) ?? false));

    final bool isEmpty = hasAnswer && children.isEmpty && held.isEmpty;

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
        'products': _subtreeCount(node),
      }),
      backLabel: Lang.get('screens.location.back'),
      backFallback: '/locations',
      actions: [
        MSButton(
          onPressed: () => MagicRoute.to('/locations/new'),
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
        _buildDelete(context, isEmpty, node),
      ],
    );
  }

  /// What is physically on this shelf.
  Widget _buildHeld(List<ProductListItem> held) {
    return SectionCard(
      label: Lang.get('screens.location.here_group'),
      count: plural('screens.location.product_count', held.length, {'count': held.length}),
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
            // The server id when there is one. Every tap on a product now reaches an endpoint, so a
            // route carrying a NAME 404s; the fallback keeps the fixture-only previews navigating.
            onTap: () => MagicRoute.to('/products/${item.id ?? Uri.encodeComponent(item.name)}'),
          ),
      ],
    );
  }

  /// The places inside this one, with their own totals.
  Widget _buildChildren(List<LocationNode> children) {
    return SectionCard(
      label: Lang.get('screens.location.children_group'),
      count: plural(
        'screens.location.location_count',
        children.length,
        {'count': children.length},
      ),
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
            colour: child.colour,
            // Descending into a child is the whole point of a tree screen.
            onTap: () => MagicRoute.to('/locations/${Uri.encodeComponent(child.path)}'),
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

  /// Removing the place, which is refused while anything is in it.
  ///
  /// ### Why refusal rather than a cascade
  ///
  /// Deleting a location that holds stock has no good silent answer. Cascading would destroy stock
  /// records the ledger is built to never lose; orphaning would leave lots pointing at nothing and
  /// break invariant 3, which says every movement references a lot belonging to the same location.
  /// Moving the contents somewhere is a real decision and it is the USER's, not a side effect of
  /// tapping delete.
  ///
  /// So a location that holds anything cannot be deleted, and the screen says what to do instead.
  /// That is the same shape as rejecting a negative stock movement: the constraint is stated where
  /// the user is rather than discovered at submit time.
  ///
  /// ### Quiet, and at the bottom
  ///
  /// This is not the action the screen exists for, so D70's pinning does not apply to it. A
  /// destructive control next to `Buraya stok gir` would be two competing answers to "what do I do
  /// on this screen"; at the bottom, in ghost, it is findable and not offered.
  Widget _buildDelete(BuildContext context, bool isEmpty, LocationNode node) {
    return SectionCard(
      label: Lang.get('screens.location.manage_group'),
      children: [
        WText(
          isEmpty
              ? Lang.get('screens.location.delete_note')
              : Lang.get('screens.location.delete_blocked'),
          className: 'text-xs text-fg-muted',
        ),
        MSButton(
          onPressed: isEmpty
              ? () => MagicStarterConfirmDialog.show(
                  context,
                  title: Lang.get('screens.location.delete_title', {'name': node.name}),
                  description: Lang.get('screens.location.delete_description'),
                  confirmLabel: Lang.get('screens.location.delete_confirm'),
                  variant: ConfirmDialogVariant.danger,
                )
              : null,
          disabled: !isEmpty,
          intent: ButtonIntent.ghost,
          className: 'py-3.5 axis-min',
          // **The label carries the disabled state, because the ghost intent does not.** Rendered
          // disabled, a ghost button is indistinguishable from a live one: black text on a card.
          // Sitting directly under a sentence that says the location cannot be deleted, that is a
          // control which looks tappable, is not, and contradicts the line above it. A light-mode
          // pass caught it; dark mode read the same way and hid nothing, this one was simply never
          // looked at until now.
          child: WText(
            Lang.get('screens.location.delete'),
            className: isEmpty ? 'text-sm font-medium text-fg' : 'text-sm font-medium text-fg-disabled',
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
