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

import '../../../app/models/app_preferences.dart';
import '../../../ui/components/list_footer/list_footer.dart';
import '../../../ui/components/location_row/location_row.dart';
import '../../../app/controllers/location_controller.dart';
import '../../../app/models/location_node.dart';
import 'location_fixtures.dart';
import '../../../ui/components/section_card/section_card.dart';

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

/// The location hierarchy: where a tenant keeps things.
///
/// **Nothing in the app showed this tree until now**, even though every screen assumed
/// it: the product detail lists stock per location, the filter offers locations as chips,
/// the stock-in sheet suggests one. All of them presented a flat set of paths, so the
/// structure the schema maintains (`parent_location_id`, a materialised `path`, a depth
/// capped at 6) existed nowhere a user could see or edit it.
///
/// ### The automation dial is reachable from here AND from settings
///
/// `location-assignment.md` makes placement automation a user-set dial, and the first
/// version put it on this screen only, below the tree, reasoning that a setting belongs
/// beside what it governs. Half of that survives: the shortcut here is worth having,
/// because this is where a user forms an opinion about placement.
///
/// The other half was wrong twice. Below an unbounded list, the control is unreachable for
/// exactly the tenants who have enough locations to care. And a preference that exists on
/// one screen only is a preference nobody finds, because settings is where people look. So
/// the value lives in `AppPreferences`, settings owns the canonical copy, and this screen
/// renders a folded shortcut to the same stored value.
///
/// **Full-auto is gated on a measured reversion rate, not a predicted confidence.** The
/// doc is explicit: if the tenant's corrections exceed the threshold the action drops back
/// to semi-auto and the user is told why. So the dial is a request, not a guarantee, and
/// the screen says so rather than implying the setting is the last word.
@immutable
class LocationIndexView extends StatefulWidget {
  /// Whether the tenant has no locations yet.
  final bool isEmpty;

  /// Which locations are shown.
  final LocationScope scope;

  /// Nodes supplied by the caller, which is how the preview catalog stays offline.
  ///
  /// Null means "read [LocationController]", which is what the route does. The preview passes
  /// [locationTree] instead, and that is not a second fixture in a wired screen: it is the same
  /// contract filled from a different source, and it is the only way the catalog can render this
  /// screen with no backend and no authenticated tenant behind it. Same split as the product list.
  ///
  /// The state class only touches the controller when this is null, so a preview never instantiates
  /// it and never issues a request.
  final List<LocationNode>? nodes;

  /// Creates the [LocationIndexView], reading from [LocationController].
  const LocationIndexView({super.key, this.nodes}) : isEmpty = false, scope = LocationScope.all;

  /// Creates the view for a tenant with no locations yet.
  const LocationIndexView.empty({super.key})
    : nodes = const <LocationNode>[],
      isEmpty = true,
      scope = LocationScope.all;

  /// Creates the view narrowed to empty places, which is its own reviewable state.
  ///
  /// **A filtered tree loses its ancestors, and that is the case worth seeing.** Filtering
  /// to empty shelves hides the rooms they sit in, so a row indented two levels under
  /// nothing reads as broken. The filtered view shows each match with its PATH instead of
  /// its indent, which is the one place `LocationRow`'s own-name rule has to give way:
  /// with no tree on screen, the path is the only context left.
  const LocationIndexView.filtered({super.key, this.nodes})
    : isEmpty = false,
      scope = LocationScope.empty;

  @override
  State<LocationIndexView> createState() => _LocationIndexViewState();
}

class _LocationIndexViewState extends State<LocationIndexView> {
  static const IconData _addIcon = Icons.add_outlined;
  static const IconData _emptyIcon = Icons.location_on_outlined;
  static const IconData _searchIcon = Icons.search_outlined;
  static const IconData _noMatchIcon = Icons.search_off_outlined;

  static const List<LocationScope> _scopes = LocationScope.values;

  static const List<PlacementAutomation> _dial = PlacementAutomation.values;

  /// The controller, or null when the caller supplied its own nodes.
  LocationController? _controller;

  /// Whether the starter template is being written, so it cannot be started twice.
  ///
  /// Three creates with no unique constraint behind them: a second tap would give the tenant six
  /// locations with three pairs of identical names, which is a legal tree and an obviously wrong one.
  bool _seeding = false;

  @override
  void initState() {
    super.initState();

    if (widget.nodes != null) return;

    final LocationController controller = LocationController.instance
      ..addListener(_onControllerChanged);

    // **`onInit` has to be called here, and nothing else calls it.** `Magic.findOrPut` only
    // registers the instance, and the framework's only caller of `onInit` is `MagicView`, which this
    // screen is not. A controller reached through `.instance` from a plain `StatefulWidget`
    // therefore never initialises, and the screen would show "No locations yet" against a tenant who
    // has forty, with no request in the server log at all. The product list hit exactly this.
    if (!controller.initialized) controller.onInit();

    _controller = controller;
  }

  @override
  void dispose() {
    _controller?.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  /// Write the three starter places, then let the tree redraw with them.
  ///
  /// The failure is a toast rather than the screen's error state: the empty state is still the
  /// truth, and replacing it with an error would take away the two buttons that are the way out.
  Future<void> _seedTemplate() async {
    final LocationController? controller = _controller;

    // Null only in the preview, which renders the empty state as a design case with no session.
    if (controller == null) return;

    setState(() => _seeding = true);

    final String? failure = await controller.createTemplate();

    if (!mounted) return;

    setState(() => _seeding = false);

    if (failure != null) {
      MagicFeedback.error(Lang.get('screens.locations.title'), failure);
    }
  }

  /// Everything the screen has, whatever the source.
  List<LocationNode> get _all =>
      widget.nodes ?? _controller?.nodes ?? const <LocationNode>[];

  /// Whether the tenant genuinely has no locations, as opposed to not having them yet.
  ///
  /// A fetch that has not answered is NOT empty: the empty state offers to create a first location,
  /// so showing it while the tree is in flight invites a tenant with forty shelves to make a
  /// forty-first.
  bool get _isEmpty => widget.nodes != null
      ? widget.isEmpty
      : (_controller?.loaded ?? false) && _all.isEmpty;


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
  List<LocationNode> get _visible => switch (widget.scope) {
    LocationScope.all => _all,
    LocationScope.stocked => _all.where((LocationNode n) => n.productCount > 0).toList(),
    LocationScope.empty => _all.where((LocationNode n) => n.productCount == 0).toList(),
  };

  /// Whether the tree is being shown whole, which decides indent versus path.
  bool get _isWholeTree => widget.scope == LocationScope.all;

  /// The already-localised label for a dial position.
  static String _dialLabel(PlacementAutomation value) => switch (value) {
    PlacementAutomation.manual => Lang.get('screens.settings.mode_manual'),
    PlacementAutomation.semiAuto => Lang.get('screens.settings.mode_suggested'),
    PlacementAutomation.fullAuto => Lang.get('screens.settings.mode_auto'),
  };

  /// What a dial position actually does, in one line.
  ///
  /// Stated rather than left to the label, because "Otomatik" alone does not tell a user
  /// that a placement will happen without asking, and that is the part they would want to
  /// know before choosing it.
  static String _dialExplanation(PlacementAutomation value) => switch (value) {
    PlacementAutomation.manual => Lang.get('screens.settings.mode_manual_note'),
    PlacementAutomation.semiAuto => Lang.get('screens.settings.mode_suggested_note'),
    PlacementAutomation.fullAuto => Lang.get('screens.settings.mode_auto_note'),
  };

  @override
  Widget build(BuildContext context) {
    final int roots = _all.where((LocationNode n) => n.depth == 0).length;

    return MSPageScaffold(
      title: Lang.get('screens.locations.title'),
      subtitle: _isEmpty
          ? null
          : Lang.get('screens.locations.subtitle', {'total': _all.length, 'roots': roots}),
      // **No header action while the list is empty.** The empty state already carries a
      // full-width `Konum ekle`, so rendering the icon button too put the same action on screen
      // twice, both in primary blue, on the one screen where the call to action has to be
      // unambiguous. The labelled button is the better of the two for a first-run user, so the
      // icon waits until there is a list to add to.
      actions: _isEmpty
          ? const <Widget>[]
          : [
              MSButton(
                onPressed: () => MagicRoute.to('/locations/new'),
                className: 'min-h-11 min-w-11 justify-center',
                semanticLabel: Lang.get('screens.locations.add'),
                child: const WIcon(_addIcon),
              ),
            ],
      children: [
        if (_isEmpty)
          _buildEmpty()
        else ...[
          // The dial goes ABOVE the tree because the tree does not end. See
          // [_buildAutomation] for why that is a correctness problem rather than a
          // preference about ordering.
          _buildAutomation(),
          _buildSearch(),
          if (_visible.isEmpty) _buildNoMatch() else _buildTree(),
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
          selectedIndex: _scopes.indexOf(widget.scope),
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
      count: Lang.get('screens.locations.node_count', {'count': nodes.length}),
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
            colour: node.colour,
            // The tree was browsable and not inspectable: a row said "Kiler, 4 ürün" and had
            // nowhere to go. `inventory-core.md` lists seeing inside a location as one of the
            // seven things the user does.
            // **Encoded, because this segment is a materialised PATH and not an id.** A node's path
            // is `Mutfak › Buzdolabı`: spaces, a `›`, and Turkish letters, none of which survive a
            // raw interpolation into a URL. It was invisible under the hash strategy, which never
            // sends the fragment anywhere; with real URLs the address bar now carries it, so an
            // unencoded space ends the path and the route matches nothing.
            //
            // Encoding makes it legal, not correct: the route is `/locations/:id` and this hands it
            // a path, which is the same fixture-era stand-in `ProductRow` carries for a product
            // without an id. It resolves when the tree is wired to the endpoint.
            onTap: () => MagicRoute.to('/locations/${Uri.encodeComponent(node.path)}'),
          ),
        // Ten locations do not need paging, and pretending otherwise would be a footer
        // that never fires. It states the total instead, which is the number worth having
        // at the bottom of a list.
        ListFooter(
          state: ListFooterState.end,
          totalLabel: Lang.get('screens.locations.all_of_them', {'count': nodes.length}),
        ),
      ],
    );
  }

  /// The placement dial, with what it does spelled out.
  ///
  /// ### Above the list, and folded shut
  ///
  /// This card used to sit BELOW the location tree, on the argument that a setting belongs
  /// beside what it governs. Anılcan named what that ignores: the tree scrolls without
  /// bound, so a control under it is reachable only by a tenant with few enough locations
  /// not to need it. Anything downstream of an unbounded list is unreachable by
  /// construction, and no amount of scrolling fixes it.
  ///
  /// Folded rather than merely moved, because a full dial pinned above every visit to this
  /// screen taxes the common case (look something up) to serve the rare one (change how
  /// placement works). The header carries the CURRENT position as its count, so the state
  /// is readable without opening it: a collapsed section that hides which mode is active
  /// would be worse than the version this replaces.
  ///
  /// It is also mirrored in settings, which is where a user goes looking for a preference.
  /// Two doors to one stored value, not two values.
  Widget _buildAutomation() {
    return ListenableBuilder(
      listenable: AppPreferences.instance,
      builder: (BuildContext context, Widget? _) {
        final PlacementAutomation current = AppPreferences.instance.placementAutomation;

        return SectionCard(
          label: Lang.get('screens.settings.placement_group'),
          count: _dialLabel(current),
          collapsible: true,
          initiallyExpanded: false,
          children: [
            WDiv(
              className: 'flex flex-col gap-2 py-1',
              children: [
                MSSegmentedControl<PlacementAutomation>(
                  options: _dial.map(_dialLabel).toList(),
                  selectedIndex: _dial.indexOf(current),
                  onChanged: (int index) =>
                      AppPreferences.instance.setPlacementAutomation(_dial[index]),
                ),
                WText(_dialExplanation(current), className: 'text-xs text-fg-muted'),
              ],
            ),
          ],
        );
      },
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
          onPressed: () => MagicRoute.to('/locations/new'),
          fullWidth: true,
          className: 'justify-center',
          child: WText(Lang.get('screens.locations.add')),
        ),
        MSButton(
          // **It used to route to the form, which is what the button above it does.** Two buttons
          // with different labels doing the same thing is worse than one, and the template is the
          // whole reason a first-run user would take the second: it hands them three places to put
          // things instead of one form to fill in three times.
          onPressed: _seeding ? null : _seedTemplate,
          disabled: _seeding,
          intent: ButtonIntent.ghost,
          fullWidth: true,
          className: 'justify-center',
          child: WText(Lang.get('screens.locations.empty_template')),
        ),
      ],
    );
  }
}
