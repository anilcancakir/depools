import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart'
    show
        ButtonIntent,
        MSButton,
        MSEmptyState,
        MSInput,
        MSPageScaffold,
        MSSegmentedControl;

import '../../../ui/components/list_footer/list_footer.dart';
import '../../../ui/components/location_row/location_row.dart';
import 'location_fixtures.dart';
import '../../../ui/components/section_card/section_card.dart';

/// How much the app decides about placement on its own.
///
/// `location-assignment.md`'s dial, verbatim. The names are its names so no translation
/// layer is needed between the setting and the behaviour it controls.
enum PlacementAutomation {
  /// The user always picks. Nothing is proposed.
  manual,

  /// A location is proposed with a visible reason. The user confirms or overrides.
  semiAuto,

  /// The location is assigned without asking. Undoable, and in the activity feed.
  fullAuto,
}

/// Which locations the list is narrowed to.
///
/// Three positions rather than a full filter sheet, because a location tree has one axis
/// worth filtering: whether a place currently holds anything. A tenant hunting an empty
/// shelf to put something on, and one auditing what is where, are the two real cases.
enum LocationScope {
  /// Everything, including empty places.
  all,

  /// Only places currently holding stock.
  stocked,

  /// Only empty places, which is what a user looks for when deciding where to put
  /// something new.
  empty,
}

/// One node in the fixture tree.
@immutable
class LocationNode {
  /// The location's own name.
  final String name;

  /// Depth, 0 for a root.
  final int depth;

  /// Products in the subtree.
  final int productCount;

  /// The already-formatted contents line.
  final String summary;

  /// The full ancestor path, used when the tree is filtered and the indent loses meaning.
  final String path;

  /// The location's icon, from `locations.icon_id`.
  ///
  /// **Every node has one, children included.** A tree where only roots carry a glyph
  /// makes the children look like text under a heading rather than like places, and the
  /// schema gives every location an `icon_id` precisely because a shelf is as much a place
  /// as a room is.
  final IconData icon;

  /// Creates a [LocationNode].
  const LocationNode({
    required this.name,
    required this.depth,
    required this.productCount,
    required this.summary,
    required this.icon,
    required this.path,
  });
}

/// The location hierarchy: where a tenant keeps things.
///
/// **Nothing in the app showed this tree until now**, even though every screen assumed
/// it: the product detail lists stock per location, the filter offers locations as chips,
/// the stock-in sheet suggests one. All of them presented a flat set of paths, so the
/// structure the schema maintains (`parent_location_id`, a materialised `path`, a depth
/// capped at 6) existed nowhere a user could see or edit it.
///
/// ### The automation dial lives here, not in settings
///
/// `location-assignment.md` makes placement automation a user-set dial. It belongs on this
/// screen rather than buried in preferences, because the thing it automates is exactly
/// what this screen is about, and because the dial is only meaningful once the user has a
/// tree for it to choose from.
///
/// **Full-auto is gated on a measured reversion rate, not a predicted confidence.** The
/// doc is explicit: if the tenant's corrections exceed the threshold the action drops back
/// to semi-auto and the user is told why. So the dial is a request, not a guarantee, and
/// the screen says so rather than implying the setting is the last word.
@immutable
class LocationIndexView extends StatelessWidget {
  static const IconData _addIcon = Icons.add_outlined;
  static const IconData _emptyIcon = Icons.location_on_outlined;
  static const IconData _searchIcon = Icons.search_outlined;
  static const IconData _noMatchIcon = Icons.search_off_outlined;

  static const List<LocationScope> _scopes = LocationScope.values;

  static const List<PlacementAutomation> _dial = PlacementAutomation.values;

  /// Whether the tenant has no locations yet.
  final bool isEmpty;

  /// Where the dial currently sits.
  final PlacementAutomation automation;

  /// Which locations are shown.
  final LocationScope scope;

  /// Creates the [LocationIndexView].
  const LocationIndexView({super.key})
    : isEmpty = false,
      automation = PlacementAutomation.semiAuto,
      scope = LocationScope.all;

  /// Creates the view for a tenant with no locations yet.
  const LocationIndexView.empty({super.key})
    : isEmpty = true,
      automation = PlacementAutomation.semiAuto,
      scope = LocationScope.all;

  /// Creates the view narrowed to empty places, which is its own reviewable state.
  ///
  /// **A filtered tree loses its ancestors, and that is the case worth seeing.** Filtering
  /// to empty shelves hides the rooms they sit in, so a row indented two levels under
  /// nothing reads as broken. The filtered view shows each match with its PATH instead of
  /// its indent, which is the one place `LocationRow`'s own-name rule has to give way:
  /// with no tree on screen, the path is the only context left.
  const LocationIndexView.filtered({super.key})
    : isEmpty = false,
      automation = PlacementAutomation.semiAuto,
      scope = LocationScope.empty;

  /// The tree, flattened in reading order with its depths.
  ///
  /// Flat plus a depth rather than nested children, because that is what the screen
  /// renders and what a materialised `path` gives cheaply. Nesting the fixture would model
  /// the database and complicate the view for no gain.


  /// The already-localised label for a scope.
  static String _scopeLabel(LocationScope value) => switch (value) {
    LocationScope.all => Lang.get('screens.locations.scope_all'),
    LocationScope.stocked => Lang.get('screens.locations.scope_stocked'),
    LocationScope.empty => Lang.get('screens.locations.scope_empty'),
  };

  /// The nodes the current scope admits.
  List<LocationNode> get _visible => switch (scope) {
    LocationScope.all => locationTree,
    LocationScope.stocked => locationTree.where((n) => n.productCount > 0).toList(),
    LocationScope.empty => locationTree.where((n) => n.productCount == 0).toList(),
  };

  /// Whether the tree is being shown whole, which decides indent versus path.
  bool get _isWholeTree => scope == LocationScope.all;

  /// The already-localised label for a dial position.
  static String _dialLabel(PlacementAutomation value) => switch (value) {
    PlacementAutomation.manual => Lang.get('screens.locations.mode_manual'),
    PlacementAutomation.semiAuto => Lang.get('screens.locations.mode_suggested'),
    PlacementAutomation.fullAuto => Lang.get('screens.locations.mode_auto'),
  };

  /// What the current dial position actually does, in one line.
  ///
  /// Stated rather than left to the label, because "Otomatik" alone does not tell a user
  /// that a placement will happen without asking, and that is the part they would want to
  /// know before choosing it.
  String get _dialExplanation => switch (automation) {
    PlacementAutomation.manual => Lang.get('screens.locations.mode_manual_note'),
    PlacementAutomation.semiAuto => Lang.get('screens.locations.mode_suggested_note'),
    PlacementAutomation.fullAuto =>
      Lang.get('screens.locations.mode_auto_note'),
  };

  @override
  Widget build(BuildContext context) {
    final int roots = locationTree.where((n) => n.depth == 0).length;

    return MSPageScaffold(
      title: Lang.get('screens.locations.title'),
      subtitle: isEmpty
          ? null
          : Lang.get('screens.locations.subtitle', {'total': locationTree.length, 'roots': roots}),
      // **No header action while the list is empty.** The empty state already carries a
      // full-width `Konum ekle`, so rendering the icon button too put the same action on screen
      // twice, both in primary blue, on the one screen where the call to action has to be
      // unambiguous. The labelled button is the better of the two for a first-run user, so the
      // icon waits until there is a list to add to.
      actions: isEmpty
          ? const <Widget>[]
          : [
              MSButton(
                onPressed: () {},
                className: 'min-h-11 min-w-11 justify-center',
                semanticLabel: Lang.get('screens.locations.add'),
                child: const WIcon(_addIcon),
              ),
            ],
      children: [
        if (isEmpty)
          _buildEmpty()
        else ...[
          _buildSearch(),
          if (_visible.isEmpty) _buildNoMatch() else _buildTree(),
          _buildAutomation(),
        ],
      ],
    );
  }

  /// Search and scope, in the shape the stock list already established.
  ///
  /// Deliberately the same layout as the product list: a full-width field with the scope
  /// beneath it. Two list screens in one app that search differently is a cost paid on
  /// every visit, and the tree does not need a different affordance to be searched.
  ///
  /// **Search and scope belong in the URL; the scroll cursor does not.** A filtered list is
  /// worth addressing and sharing, a scroll position is not, so a reload returns to the top
  /// of the same filtered list.
  Widget _buildSearch() {
    return WDiv(
      className: 'flex flex-col gap-2',
      children: [
        // **A real field, not a picture of one.** This was a `WDiv` holding a magnifier and a
        // `WText`: it looked exactly like a search box and had no gesture at all, so tapping it
        // did nothing on either platform. A control that cannot be used is worse than an absent
        // one, because the user spends a tap finding out.
        //
        // The input tone is correct HERE and only here. This field sits on the PAGE rather than on
        // a card, so `bg-surface-container-high` is `#E5E5EA` on `#F2F2F7`: slightly recessed,
        // which is what an input well is meant to look like and what iOS search fields do. The
        // rule it would break is on a white CARD, where the same token reads as disabled.
        MSInput(
          className: 'bg-surface-container-high',
          placeholder: Lang.get('screens.locations.search'),
          prefix: const WIcon(_searchIcon, className: 'size-4 text-fg-muted'),
          onChanged: (String _) {},
        ),
        MSSegmentedControl<LocationScope>(
          options: _scopes.map(_scopeLabel).toList(),
          selectedIndex: _scopes.indexOf(scope),
          onChanged: (_) {},
        ),
      ],
    );
  }

  /// A scope that admits nothing, which is not the same as having no locations.
  Widget _buildNoMatch() {
    return WDiv(
      className: 'flex flex-col gap-3 p-4 rounded-lg bg-surface-container',
      children: [
        WDiv(
          className: 'w-full',
          child: MSEmptyState(
            icon: _noMatchIcon,
            title: Lang.get('screens.locations.filtered_empty'),
            description: Lang.get(
              'screens.locations.filtered_hint',
              {'total': locationTree.length},
            ),
          ),
        ),
      ],
    );
  }

  /// The tree itself, in reading order, or the matches with their paths when filtered.
  Widget _buildTree() {
    final List<LocationNode> nodes = _visible;

    return SectionCard(
      label: _isWholeTree ? Lang.get('screens.locations.layout_group') : Lang.get('screens.locations.matches_group'),
      count: '${nodes.length} konum',
      children: [
        for (final LocationNode node in nodes)
          LocationRow(
            // A filtered list has no ancestors on screen, so the row falls back to its
            // path. Keeping the indent there would leave a row inset two levels under
            // nothing.
            name: _isWholeTree ? node.name : node.path,
            depth: _isWholeTree ? node.depth : 0,
            productCount: node.productCount,
            itemSummary: node.summary,
            icon: node.icon,
            onTap: () {},
          ),
        // Ten locations do not need paging, and pretending otherwise would be a footer
        // that never fires. It states the total instead, which is the number worth having
        // at the bottom of a list.
        ListFooter(state: ListFooterState.end, totalLabel: '${nodes.length} konumun hepsi'),
      ],
    );
  }

  /// The placement dial, with what it does spelled out.
  Widget _buildAutomation() {
    return SectionCard(
      label: Lang.get('screens.locations.placement_group'),
      children: [
        WDiv(
          className: 'flex flex-col gap-2 py-1',
          children: [
            MSSegmentedControl<PlacementAutomation>(
              options: _dial.map(_dialLabel).toList(),
              selectedIndex: _dial.indexOf(automation),
              onChanged: (_) {},
            ),
            WText(_dialExplanation, className: 'text-xs text-fg-muted'),
          ],
        ),
      ],
    );
  }

  /// The first-run state, which is where every tenant starts.
  ///
  /// A tenant with no locations cannot receive stock anywhere, so this is not a decorative
  /// empty state: it is a blocker with one way out. The two suggested starting points are
  /// the ones `location-assignment.md`'s scenario is written around.
  Widget _buildEmpty() {
    return WDiv(
      className: 'flex flex-col gap-3 p-4 rounded-lg bg-surface-container',
      children: [
        WDiv(
          className: 'w-full',
          child: MSEmptyState(
            icon: _emptyIcon,
            title: Lang.get('screens.locations.empty_title'),
            description:
                Lang.get('screens.locations.empty_description'),
          ),
        ),
        MSButton(
          onPressed: () {},
          fullWidth: true,
          className: 'justify-center',
          child: WText(Lang.get('screens.locations.add')),
        ),
        MSButton(
          onPressed: () {},
          intent: ButtonIntent.ghost,
          fullWidth: true,
          className: 'justify-center',
          child: WText(Lang.get('screens.locations.empty_template')),
        ),
      ],
    );
  }
}
