import 'dart:async';
import 'dart:math' as math;

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
        MagicStarter;

import '../../../app/controllers/product_controller.dart';
import '../../../app/models/product_filter.dart';
import '../../../ui/components/filter_bar/filter_bar.dart';
import '../../../ui/components/list_footer/list_footer.dart';
import '../../../ui/components/product_row/product_row.dart';
import '../../../ui/components/section_card/section_card.dart';
import 'product_filter_sheet.dart';
import 'activity_panel.dart';
import 'product_fixtures.dart';

/// Stock list: every product the tenant holds, and the home surface in inventory mode.
///
/// This screen is where a new user lands, so `product.md`'s first success criterion
/// lives here: ten items into stock in under five minutes without reading anything.
/// That is why the empty state offers the three fastest capture paths rather than a
/// "Create product" button, and why the paths are ordered by speed rather than by how
/// much control they give.
///
/// **It is deliberately built almost entirely from what the product detail screen
/// already needed.** `SectionCard`, `Quantity` and `ExpiryBadge` come across
/// unchanged, and only `ProductRow` is new, which is the argument for having designed
/// the detail screen first: its primitives paid for this one.
///
/// **The action-placement rule gains a distinction here, and both screens are better
/// for it.** `ProductShowView` puts its frequent mutations in a footer, and this screen
/// first copied that with an "Ürün ekle" button at the bottom. Wrong: on a LIST,
/// creating a new item is the canonical header action, the way iOS puts a plus in the
/// nav bar. The footer is for acting on the thing you are already looking at, which is
/// what stock in and out are on a detail screen.
///
/// So: **header plus creates a new item in this collection, footer acts on the item you
/// are viewing.** Card headers still navigate only, and search and filter sit at the
/// top because they change what you look at rather than the data.
///
/// ### Filtering
///
/// Three surfaces with one job each, designed in
/// `docs/depools-system/features/filtering-and-saved-views.md`: the search field for
/// free text, [FilterBar] for saved filters and for showing what is in force, and
/// [ProductFilterSheet] for the full axis set.
///
/// **The applied filter is always visible while it applies.** That is not polish. The
/// documented reason mobile filtering fails is not the axis count, it is a shortened
/// list with no indication of why: the user concludes the product is not there and
/// leaves. Any review of this screen checks that first.
///
/// ### Where the filtering happens, and why it moved
///
/// On the SERVER, through [ProductController]. It used to happen here, over the rows the controller
/// had loaded, and that was correct while the endpoint answered the whole collection. It stops being
/// correct the moment the list is a page: a filter over thirty rows can only find what those thirty
/// held, so "expired" would report three items on page one and three different ones on page two.
///
/// So the view stopped owning the filter. [ProductController.filter] is the single copy, the chips
/// and the sheet write to it through [ProductController.apply], and the rows arrive already narrowed.
/// The preview catalog still filters locally against [ProductIndexView.items], because there is no
/// server behind it; that is the one place two paths exist, and it is why [_visible] reads the
/// controller when there is one instead of filtering unconditionally.
class ProductIndexView extends StatefulWidget {
  /// Whether the tenant has no products at all yet.
  final bool isEmpty;

  /// Whether a further page is in flight.
  ///
  /// **The list is cursor-paginated, not offset.** In an inventory app stock changes while
  /// the user scrolls, and an offset page skips or repeats rows the moment anything above
  /// the window moves. A cursor on the sort key is stable under insertion.
  ///
  /// The search and the filter go in the URL; the cursor does not. A filtered list is worth
  /// addressing and sharing, a scroll position is not, so a reload lands at the top of the
  /// same filtered list.
  final bool isLoadingMore;

  /// Rows supplied by the caller, which is how the preview catalog stays offline.
  ///
  /// Null means "read [ProductController]", which is what the route does. The preview passes
  /// [productFixtures] instead, and that is not a second fixture in a wired screen: it is the
  /// same contract filled from a different source, and it is the only way the catalog can
  /// render this screen without a backend and an authenticated tenant behind it.
  ///
  /// The state class only touches the controller when this is null, so a preview never
  /// instantiates it and never issues a request.
  final List<ProductListItem>? items;

  /// Creates the [ProductIndexView], reading from [ProductController].
  const ProductIndexView({super.key, this.items}) : isEmpty = false, isLoadingMore = false;

  /// Creates the view for a tenant with no products yet.
  const ProductIndexView.empty({super.key})
    : items = const <ProductListItem>[],
      isEmpty = true,
      isLoadingMore = false;

  /// Creates the view with a page in flight, which is its own reviewable state.
  ///
  /// A paginated list spends real time here on a slow connection, and a footer that looks
  /// like the end of the data is how a user stops scrolling with rows left unseen.
  const ProductIndexView.loadingMore({super.key, this.items})
    : isEmpty = false,
      isLoadingMore = true;

  @override
  State<ProductIndexView> createState() => _ProductIndexViewState();
}

class _ProductIndexViewState extends State<ProductIndexView> {
  static const IconData _searchIcon = Icons.search_outlined;
  static const IconData _filterIcon = Icons.filter_list_outlined;
  static const IconData _scanIcon = Icons.qr_code_scanner_outlined;
  static const IconData _activityIcon = Icons.history;
  static const IconData _receiptIcon = Icons.receipt_long_outlined;
  static const IconData _photoIcon = Icons.photo_camera_outlined;
  static const IconData _addIcon = Icons.add_outlined;

  /// How long after the last keystroke the search is sent.
  ///
  /// The query is a server request now, so a request per character would be thirty requests to type
  /// a product name. 350ms is the pause that reads as "finished typing a word" without the user
  /// noticing they waited.
  static const Duration _searchDelay = Duration(milliseconds: 350);

  /// How many pages a shared link may ask a cold client to fetch.
  ///
  /// The URL is editable by whoever holds it, and each page is a request, so this is a ceiling on
  /// what a stranger's link can cost rather than a limit anybody legitimately reaches.
  static const int _maxSharedPages = 50;

  /// How close to the bottom, in logical pixels, the next page is asked for.
  ///
  /// Roughly three rows' worth, so the page is already in flight while the user is still reading
  /// what they have rather than arriving after they hit the end and stopped.
  static const double _loadMoreThreshold = 240;

  /// The filter, for the preview catalog only.
  ///
  /// A wired screen reads [ProductController.filter] instead; see [_filter]. This exists because the
  /// catalog has no controller and no server, and a sheet that could not filter the fixtures would
  /// make the whole screen unreviewable there.
  ProductFilter _localFilter = const ProductFilter();

  final TextEditingController _search = TextEditingController();

  Timer? _searchDebounce;

  /// The scroll the shell put above this page, watched for the bottom of the list.
  ///
  /// **The scrollable is an ANCESTOR, which rules out the obvious approach.** A
  /// `NotificationListener<ScrollNotification>` placed among this page's children never fires,
  /// because a scroll notification travels UP from the `Scrollable` and this page is below it.
  /// `Scrollable.maybeOf` looks the other way, which is the direction the widget actually lies in.
  ScrollPosition? _scroll;

  /// Filters saved by the user, on top of the built-ins.
  ///
  /// Local for now: the persistence question ("per user or per team") is recorded as
  /// open in the feature doc, and guessing it here would bake the guess into a
  /// migration.
  final List<SavedProductFilter> _userSaved = <SavedProductFilter>[];

  List<SavedProductFilter> get _saved => <SavedProductFilter>[
    ...SavedProductFilter.builtIns,
    ..._userSaved,
  ];

  /// Null in the preview, where [ProductIndexView.items] supplies the rows instead.
  ///
  /// Created in [initState] rather than read through a getter, because `Magic.findOrPut`
  /// INSTANTIATES on first read and the controller loads in `onInit`: a getter would fire a
  /// request from the catalog the moment this screen was previewed.
  ProductController? _controller;

  @override
  void initState() {
    super.initState();

    if (widget.items == null) {
      final ProductController controller = ProductController.instance
        ..addListener(_onControllerChanged);

      // **`onInit` has to be called here, and nothing else calls it.** `Magic.findOrPut` only
      // registers the instance, and the only caller of `onInit` in the framework is `MagicView`,
      // which this screen is not. So a controller reached through `.instance` from a plain
      // `StatefulWidget` never initialises: the screen showed "No products yet" against a tenant
      // holding eleven, with no request in the server log at all, which is `flutter-app.md`'s
      // "onInit alone never fires for a non-backing controller" reproduced exactly.
      //
      // Guarded on `initialized` rather than called unconditionally, because the controller is
      // keyed by type and outlives this screen: a second visit would otherwise refetch on every
      // navigation. `onInit` itself sets that flag, so this is the same once-only contract a
      // `MagicView` would give it.
      if (!controller.initialized) controller.onInit();

      _controller = controller;
      _applyUrl(controller);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Attached here rather than in `initState`, because the ancestor `Scrollable` is only reachable
    // once this element has its dependencies. Re-resolved on every call and compared, so a shell that
    // rebuilds its scroll view does not leave the listener on a dead position.
    final ScrollPosition? position = _controller == null ? null : Scrollable.maybeOf(context)?.position;

    if (position == _scroll) return;

    _scroll?.removeListener(_onScroll);
    _scroll = position;
    _scroll?.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _search.dispose();
    _scroll?.removeListener(_onScroll);
    _controller?.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  /// Asks for the next page as the bottom of the list comes into reach.
  ///
  /// The controller absorbs the repeats: this fires on every scroll frame while inside the threshold,
  /// and `loadMore` returns immediately unless there is a cursor and nothing in flight.
  void _onScroll() {
    final ScrollPosition? position = _scroll;

    if (position == null || !position.hasContentDimensions) return;

    if (position.maxScrollExtent - position.pixels <= _loadMoreThreshold) {
      // The URL follows the page count, so a link copied after scrolling reproduces the rows the
      // sender was looking at rather than only the filter they had applied.
      _controller?.loadMore().then((_) {
        if (mounted) _syncUrl();
      });
    }
  }

  /// What is narrowing the list.
  ///
  /// The controller's copy when there is one, so the chips can never describe a filter other than the
  /// one the rows were fetched with. The local field is the preview's.
  ProductFilter get _filter => _controller?.filter ?? _localFilter;

  /// Adopts the filter a URL carries, which is what makes a shared link reproduce what was sent.
  ///
  /// Read from `currentLocation` and parsed here rather than through the router's own
  /// `queryParameters`: that one is a `Map<String, String>` and keeps only the last value of a
  /// repeated key, so `location_ids[]=a&location_ids[]=b` would arrive as one shelf and the list
  /// would silently be wider than the URL said. `queryParametersAll` keeps both.
  ///
  /// Does nothing when the URL carries no filter, so an ordinary visit is one request and the
  /// controller's own `onInit` load stands. `pages` is honoured only alongside a real page count,
  /// because re-fetching pages one to N costs N requests and an ordinary link should not.
  void _applyUrl(ProductController controller) {
    final Uri uri = Uri.parse(MagicRouter.instance.currentLocation ?? '');
    final ProductFilter fromUrl = ProductFilter.fromQueryParameters(uri.queryParametersAll);
    final int pages = int.tryParse(uri.queryParameters['pages'] ?? '') ?? 1;

    if (fromUrl.isEmpty && pages <= 1) return;

    // After the frame: `onInit` above may already have a load in flight, and the controller's own
    // request-sequence guard is what makes this one win rather than the two racing.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      await controller.apply(fromUrl);

      // Capped, because `pages` arrives from a URL a stranger can edit, and fifty is far past
      // anything a shared link should ask a cold client to fetch.
      //
      // `math.min` rather than `clamp`, for the same legibility reason recorded on the other side of
      // this file: `clamp` type-checks here only because the analyzer special-cases `num.clamp` to
      // return `int` when the receiver and both bounds are `int`, and a reviewer read it as a type
      // error. The lower bound was redundant anyway, since this line is already inside `pages > 1`.
      if (pages > 1) await controller.loadPages(math.min(pages, _maxSharedPages));
    });
  }

  /// The filter written into this screen's own URL, so a link reproduces what the sender saw.
  ///
  /// **`replace`, never `to`.** A push per keystroke would fill the history with one entry per
  /// letter of a search term, and the back button would then walk the user backwards through their
  /// own typing instead of off the screen.
  ///
  /// The page COUNT rides along and the cursor deliberately does not. A cursor encodes a row's
  /// position in one ordered result, so a shared one lands the reader in the middle of a list with
  /// nothing above it, and points at nothing at all once that row is renamed or consumed. A count
  /// re-fetches pages one to N, which is the same rows in the same order with the top intact, and it
  /// stays meaningful however the data moves underneath it.
  void _syncUrl() {
    final ProductController? controller = _controller;

    if (controller == null) return;

    final int pages = controller.loadedPages;

    MagicRoute.replace(
      '/products?${controller.filter.toQueryString(extra: <String, Object?>{
        // Omitted at one, which is the common case, so an ordinary link stays short.
        if (pages > 1) 'pages': pages,
      })}',
    );
  }

  /// Applies a filter, wherever it has to go.
  void _setFilter(ProductFilter next) {
    // Keep the field and the query in step in both directions. Removing the text criterion with the
    // chip's X has to empty the field too, or the box goes on showing a term that is no longer
    // filtering anything.
    if (_search.text != next.query) _search.text = next.query;

    final ProductController? controller = _controller;

    if (controller == null) {
      setState(() => _localFilter = next);

      return;
    }

    controller.apply(next).then((_) {
      if (mounted) _syncUrl();
    });
  }

  /// Every row the screen knows about.
  ///
  /// On a wired screen this is one page of an already-narrowed list, which is why the counts below
  /// come from the controller rather than from `.length`.
  List<ProductListItem> get _all =>
      widget.items ?? _controller?.items ?? const <ProductListItem>[];

  /// The rows to render.
  ///
  /// Already narrowed by the server when there is a controller. The local pass is the preview's only.
  List<ProductListItem> get _visible => _controller != null
      ? _all
      : _all.where((item) => item.matches(_localFilter)).toList();

  /// How many rows match the current filter in total, not how many are loaded.
  int get _matchCount => _controller?.total ?? _visible.length;

  /// How many products the tenant holds with nothing narrowing the list.
  int get _catalogueCount => _controller?.catalogueTotal ?? _all.length;

  /// How many rows a draft filter would match.
  ///
  /// A request on a wired screen, and the loaded fixtures in the catalog. Both answer the same
  /// question about the same source the list renders from, which is the property the sheet needs.
  Future<int?> _countMatches(ProductFilter draft) async {
    final ProductController? controller = _controller;

    if (controller != null) return controller.countFor(draft);

    return _all.where((item) => item.matches(draft)).length;
  }

  /// The locations the filter sheet offers.
  ///
  /// From the controller when there is one, because a chip for a location this tenant does not
  /// have is a filter that can only ever match nothing.
  List<FilterOption> get _locationOptions => _controller?.locations ?? locationOptions;

  /// The tag options, derived from the rows that are loaded.
  ///
  /// **A fixture list here could not match anything.** The sheet was handed `tagOptions`, a constant,
  /// so its tag chips offered `soğuk zincir` and `sarf` against a tenant that has neither and none of
  /// the tags it does have. Two of the five axes were inert in exactly that way; this is one of them.
  ///
  /// Derived rather than fetched, because there is nothing to fetch: the payload sends each product's
  /// tag NAMES, and the filter matches on the name too (`ProductResource` explains why it sends names
  /// rather than id pairs). So the union of what is loaded IS the set worth offering, and a tag that
  /// matches nothing cannot appear.
  ///
  /// Sorted, because a set has no order and chips that reshuffle between openings are unusable.
  ///
  /// **Derived from [_all] unconditionally, with no fixture fallback.** A `_controller == null` branch
  /// returning the constant was the first shape and it reintroduced the same defect in the preview:
  /// chips offering `soğuk zincir` and `sarf` against fixture rows that carry neither. `_all` is
  /// already `widget.items ?? _controller?.items`, so one expression serves the catalog and the wired
  /// screen, and in both a tag that matches nothing cannot appear.
  List<FilterOption> get _tagOptions {
    final List<String> names = _all.expand((i) => i.tags).toSet().toList()..sort();

    return <FilterOption>[for (final String name in names) FilterOption(id: name, label: name)];
  }

  /// Whether this tenant genuinely has nothing yet, as opposed to a filter matching nothing.
  bool get _isEmptyCatalogue => widget.isEmpty || (_controller?.isEmpty ?? false);

  /// The signed-in tenant's own name, for the subtitle.
  ///
  /// This was the literal `'Mutfak Deposu'`, which was invisible while the screen ran on
  /// fixtures and becomes a lie the moment it runs on real data: it would name someone else's
  /// team on every screen. Falls back to the product name rather than to an empty string,
  /// because a subtitle reading "· 11 products" with nothing in front of it looks broken.
  String get _teamName =>
      MagicStarter.teamResolver?.currentTeam()?.name ?? Lang.get('app.name');

  /// The line under the page title: whose catalogue this is, and how much of it is on screen.
  ///
  /// **This is where the list's count lives now.** The card below used to carry its own
  /// `ALL PRODUCTS · 101 products` header, which repeated this line sixteen pixels lower, and the
  /// count it showed was the FILTERED one while this showed the catalogue: two numbers, two
  /// meanings, no label saying which was which.
  ///
  /// Null while the first page is in flight, not just when the catalogue is empty. The count is
  /// genuinely unknown then, and a zero next to a real team name reads as "this tenant has nothing"
  /// rather than as a pending request.
  String? get _subtitle {
    if (_isEmptyCatalogue || (_controller?.isLoading ?? false)) return null;

    // Both numbers only while a filter is narrowing, because "101 of 101" is noise. The catalogue
    // figure stays in either form: it is what makes a short list legible as a filtered one rather
    // than as a small tenant.
    if (_filter.isActive) {
      return Lang.get('screens.products.subtitle_filtered', {
        'team': _teamName,
        'count': _matchCount,
        'total': _catalogueCount,
      });
    }

    return Lang.get('screens.products.subtitle', {'team': _teamName, 'count': _catalogueCount});
  }

  Future<void> _openSheet() async {
    final ProductFilter? applied = await ProductFilterSheet.show(
      context,
      initial: _filter,
      countMatches: _countMatches,
      initialCount: _matchCount,
      locations: _locationOptions,
      // Categories are STILL the fixture list, and that is a reported gap rather than an oversight:
      // the payload sends `product_category_id` but no name, `Product` has no `category` relation to
      // eager-load, and `ProductCategory::label()` needs a locale. Wiring it is four small steps
      // across the backend and belongs with them, not here.
      categories: categoryOptions,
      tags: _tagOptions,
    );

    // Null means dismissed, which is not the same as an empty filter. Coalescing the
    // two would silently clear a filter every time the user swiped the sheet away.
    if (applied == null || !mounted) return;
    _setFilter(applied);
  }

  void _save() {
    setState(() {
      _userSaved.add(
        SavedProductFilter(
          // Name and id from the criteria for now. Prompting for a name is the right
          // interaction and it needs a text-input dialog; leaving the placeholder
          // obviously provisional beats shipping a silent "Filtre 1".
          id: 'local:${_userSaved.length + 1}',
          name: _filterSummary(_filter),
          filter: _filter,
        ),
      );
    });
  }

  /// A short name for a saved filter, built from its own criteria.
  ///
  /// Names the first two criteria and counts the rest. A single-criterion summary
  /// was the first attempt and produced "Stok yok +1" sitting next to the built-in
  /// "Stok yok", which the user cannot tell apart in a row of capsules. Two
  /// criteria is enough to make it self-describing without outgrowing a chip.
  String _filterSummary(ProductFilter filter) {
    final List<FilterCriterion> parts = filter.criteria(
      resolveLocation: resolveLocationLabel,
      resolveCategory: resolveCategoryLabel,
    );
    if (parts.isEmpty) return Lang.get('screens.products.saved_prefix');

    final String named = parts.take(2).map((c) => c.label).join(' · ');
    final int rest = parts.length - 2;
    return rest > 0 ? '$named +$rest' : named;
  }

  @override
  Widget build(BuildContext context) {
    final List<ProductListItem> visible = _visible;

    return MSPageScaffold(
      title: Lang.get('screens.products.title'),
      // Null while the first page is in flight, not just when the catalogue is empty. The count
      // is genuinely unknown then, and rendering `_all.length` reads as "0 products" next to a
      // real team name: the same false state the list body needed its own loading branch for, on
      // the one line that sits above it.
      subtitle: _subtitle,
      actions: [
        // The same entry point the assistant shell has (D50). In this mode it is the only
        // place a full-auto write becomes visible, because there is no transcript.
        MSButton(
          onPressed: () => ActivityPanel.show(context),
          intent: ButtonIntent.ghost,
          className: 'min-h-11 min-w-11 justify-center',
          semanticLabel: Lang.get('screens.products.activity'),
          child: const WIcon(_activityIcon),
        ),
        MSButton(
          onPressed: () {},
          intent: ButtonIntent.ghost,
          className: 'min-h-11 min-w-11 justify-center',
          semanticLabel: Lang.get('screens.products.scan'),
          child: const WIcon(_scanIcon),
        ),
        MSButton(
          onPressed: () => MagicRoute.to('/products/new'),
          className: 'min-h-11 min-w-11 justify-center',
          semanticLabel: Lang.get('screens.products.add'),
          child: const WIcon(_addIcon),
        ),
      ],
      children: [
        if (!_isEmptyCatalogue) ...[
          _buildSearch(),
          FilterBar(
            filter: _filter,
            saved: _saved,
            resolveLocation: resolveLocationLabel,
            resolveCategory: resolveCategoryLabel,
            onChanged: _setFilter,
            onSave: _save,
          ),
        ],
        // The order of these five is load-bearing. Loading has to come before the two empty
        // states, because both of them are FALSE while the first request is in flight and the
        // list is empty for a third reason: without this branch the screen tells a user with
        // eleven products that their filter matched nothing, which is exactly the lie this
        // screen's own documentation says any review checks for first.
        if (_controller?.isLoading ?? false)
          ..._buildSkeletons()
        else if (_controller?.isError ?? false)
          _buildLoadFailed()
        else if (_isEmptyCatalogue)
          _buildEmpty()
        else if (visible.isEmpty)
          _buildNoMatches()
        else
          ..._buildList(visible),
      ],
    );
  }

  /// Debounces a keystroke into a filter change.
  ///
  /// The text is compared against the filter before anything is sent, so re-typing the same word or
  /// a `setText` from [_setFilter] cannot start a request that would change nothing.
  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(_searchDelay, () {
      if (!mounted || value == _filter.query) return;

      _setFilter(_filter.copyWith(query: value));
    });
  }

  /// Search and filter, side by side.
  ///
  /// Both are navigation rather than mutation, which is why they sit here at the top
  /// instead of in a card header: they change what you are looking at, not the data.
  /// HIG puts an inline search field directly above the content it searches when the
  /// search is scoped to that content rather than global, which is this case.
  Widget _buildSearch() {
    return WDiv(
      className: 'flex flex-row items-center gap-2',
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
        WDiv(
          className: 'flex-1 min-w-0',
          child: MSInput(
            // **`h-11` on BOTH halves, because a shared row does not give them one.**
            // The field took its height from its own padding and the button took its from
            // `min-h-11`, so the two sat at 52 and 44 in a row that reads as one control.
            // `items-center` centred that mismatch rather than hiding it. This is the same
            // fix the assistant composer needed: one height, declared on every part.
            className: 'h-11 bg-surface-container-high',
            placeholder: Lang.get('screens.products.search'),
            prefix: const WIcon(_searchIcon, className: 'size-4 text-fg-muted'),
            // **This was `(String _) {}` and the field did nothing at all.** It looked and felt like
            // a search box, took focus and showed the typed text, and never narrowed the list. The
            // filter had a `query` axis all along and nothing wrote to it, so the most obvious
            // control on the screen was the one that was not connected.
            controller: _search,
            onChanged: _onSearchChanged,
          ),
        ),
        // **The active state is a count, not a fill.** This button turned `bg-primary` when a
        // filter was on, which put a second blue on a page whose header already carries the
        // primary `Ürün ekle`, and made the state readable only to someone who can tell blue from
        // grey. The number says more than the colour could: it tells the user how much they are
        // about to clear rather than only that something is on.
        MSButton(
          onPressed: _openSheet,
          intent: ButtonIntent.secondary,
          // `h-11` to match the field beside it; `min-w-11` rather than `w-11` because the
          // active-filter count widens the button and a fixed width would clip it.
          className: 'h-11 min-w-11 justify-center gap-1 bg-surface-container',
          semanticLabel: _filter.isActive
              ? Lang.get('screens.products.filter_active', {'count': _filter.activeCount})
              : Lang.get('screens.products.filter'),
          child: WDiv(
            className: 'flex flex-row items-center gap-1',
            children: [
              const WIcon(_filterIcon),
              if (_filter.isActive)
                WText('${_filter.activeCount}', className: 'text-xs font-semibold text-fg'),
            ],
          ),
        ),
      ],
    );
  }

  /// The first thing a new user sees, so it offers the fastest routes in, not a form.
  ///
  /// Ordered by speed rather than by control: a receipt photo enters many products at
  /// once, a barcode enters one with its details filled, a photo enters one that has
  /// no barcode, and typing is last because it is the slowest even though it is the
  /// most obvious.
  Widget _buildEmpty() {
    return WDiv(
      // MSEmptyState centres its own children, but its root Column has no width of its
      // own and its description carries `max-w-xs`, so it measures ~368px and sits at
      // the card's left edge. Giving it the card's full width is what centres it: its
      // `items-center` then has something to centre in, and the description shrinks
      // under the tighter constraint instead of overflowing. Centring the ~368px block
      // with a `justify-center` row looked identical at desktop width and overflowed by
      // 54px once the card was phone-sized, because a Row lays a non-flex child out
      // unbounded. `items-stretch` on this column was the first attempt and did not
      // reach through to the child at all.
      className: 'flex flex-col gap-3 p-4 rounded-lg bg-surface-container',
      children: [
        WDiv(
          className: 'w-full',
          child: MSEmptyState(
            icon: _receiptIcon,
            title: Lang.get('screens.products.empty_title'),
            description:
                Lang.get('screens.products.empty_description'),
          ),
        ),
        WDiv(
          className: 'flex flex-col gap-2',
          children: [
            MSButton(
              onPressed: () => MagicRoute.to('/receipt'),
              fullWidth: true,
              className: 'justify-center gap-2',
              child: WDiv(
                className: 'flex flex-row items-center gap-2',
                children: [
                  WIcon(_receiptIcon, className: 'size-4'),
                  WText(Lang.get('screens.products.empty_receipt')),
                ],
              ),
            ),
            WDiv(
              className: 'flex flex-row gap-2',
              children: [
                WDiv(
                  className: 'flex-1',
                  child: MSButton(
                    onPressed: () => MagicRoute.to('/scan'),
                    intent: ButtonIntent.secondary,
                    fullWidth: true,
                    className: 'justify-center gap-2',
                    child: WDiv(
                      className: 'flex flex-row items-center gap-2',
                      children: [
                        WIcon(_scanIcon, className: 'size-4'),
                        WText(Lang.get('screens.products.scan')),
                      ],
                    ),
                  ),
                ),
                WDiv(
                  className: 'flex-1',
                  child: MSButton(
                    onPressed: () => MagicRoute.to('/shelf-photo'),
                    intent: ButtonIntent.secondary,
                    fullWidth: true,
                    className: 'justify-center gap-2',
                    child: WDiv(
                      className: 'flex flex-row items-center gap-2',
                      children: [
                        WIcon(_photoIcon, className: 'size-4'),
                        WText(Lang.get('screens.products.empty_photo')),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            MSButton(
              onPressed: () {},
              intent: ButtonIntent.ghost,
              fullWidth: true,
              className: 'justify-center',
              child: WText(Lang.get('screens.products.empty_manual')),
            ),
          ],
        ),
      ],
    );
  }

  /// The first load, drawn as the rows that are coming rather than as a spinner.
  ///
  /// `ProductRow.skeleton()` is the row's own shadow, so the list does not jump when content
  /// lands and the placeholder cannot drift from the thing it stands in for. Five, because that
  /// is roughly a phone viewport: enough to read as a list, few enough not to imply a count.
  List<Widget> _buildSkeletons() => <Widget>[
    SectionCard(
      label: Lang.get('screens.products.all'),
      children: <Widget>[for (int i = 0; i < 5; i++) const ProductRow.skeleton()],
    ),
  ];

  /// The request failed, which is neither an empty catalogue nor an empty filter.
  ///
  /// `SectionCard` already carries an `error` plus `onRetry` pair, so this is a call rather than
  /// a hand-rolled panel: one more empty-state layout would be a second answer to a question the
  /// component library had already answered, and it would drift.
  Widget _buildLoadFailed() => SectionCard(
    label: Lang.get('screens.products.all'),
    error: _controller?.rxStatus.message ?? Lang.get('screens.products.load_failed'),
    onRetry: () => _controller?.load(),
    children: const <Widget>[],
  );

  /// A filter that matched nothing, which is a different state from an empty catalogue.
  ///
  /// The distinction is the whole point: "Henüz ürün yok" tells a user to start
  /// capturing, and showing it to someone whose 42 products are merely filtered out
  /// would be a lie about their own data. So this one names the filter as the cause
  /// and offers the way back.
  Widget _buildNoMatches() {
    return WDiv(
      className: 'flex flex-col gap-3 p-4 rounded-lg bg-surface-container',
      children: [
        WDiv(
          className: 'w-full',
          child: MSEmptyState(
            icon: _filterIcon,
            title: Lang.get('screens.products.filtered_empty'),
            description:
                Lang.get('screens.products.filtered_description', {'count': _catalogueCount}),
          ),
        ),
        MSButton(
          onPressed: () => _setFilter(const ProductFilter()),
          fullWidth: true,
          className: 'justify-center',
          child: WText(Lang.get('screens.products.filter_clear')),
        ),
      ],
    );
  }

  /// The list. ONE list, in the order the endpoint returns.
  ///
  /// **There was a separate "needs attention" section above the catalogue and it is gone.** The
  /// argument for it was that expiring and out-of-stock items are what a cafe opens this screen for
  /// daily, and the argument held right up to the point of seeing it on real data: it split one
  /// collection into two cards with two counts, and Anılcan called the design of it bad outright.
  ///
  /// Two attempts to save it are worth recording, because both failed for reasons that would apply
  /// again. Starting it OPEN pushed the catalogue most of a screen down: at eleven products six needed
  /// attention, at a hundred it was fifty-seven, so the thing the user came to look up was below the
  /// fold. Starting it CLOSED then broke filtering: "Expired" leaves fourteen products, every one of
  /// them by definition an attention row, so the catalogue card disappeared and a closed card became
  /// the whole screen, reading as "nothing found" with fourteen rows one tap away.
  ///
  /// **Nothing was lost by removing it**, which is what makes it the right call rather than a
  /// concession. The three chips above the list narrow to exactly those products in one tap, the
  /// dashboard counts them, and every row still carries its own expiry and stock badges. What went is
  /// a second grouping of the same rows, not the information.
  ///
  /// [ProductListItem.needsAttention] stays: the chips are defined by it.
  List<Widget> _buildList(List<ProductListItem> visible) {
    return <Widget>[
      if (visible.isNotEmpty)
        SectionCard(
          // **No header, because this page IS the section.** It carried
          // `ALL PRODUCTS · 101 products` directly under a page header reading `Stock` and
          // `Demo Kitchen · 101 products`: the same name and the same number, twice, sixteen pixels
          // apart. A section header earns its place when a screen holds several sections and the
          // reader has to tell them apart, which this screen stopped doing when the separate
          // "needs attention" card was removed and one list was left.
          //
          // The count moved UP rather than away: the page subtitle now states what the filter
          // matched as well as what the tenant holds, which is where a reader looks for the scope of
          // what is under it.
          //
          // The `All ›` control went with it, and it was dead: `onPressed: () {}`, pointing at
          // nothing, because there is no other list of products to go to. An affordance that costs
          // a tap to discover is inert is worse than an absent one.
          children: [
            for (final ProductListItem item in visible) _row(item),
            // The footer states the total rather than pretending to page eight fixtures.
            // The total is also the SKU count the plan meters on, so it is the one number
            // worth having at the bottom of this particular list.
            ListFooter(
              // Three states now, and the middle one is the reason this component had a
              // `loadingMore` variant nothing could reach: a page really is in flight here, so the
              // footer says so rather than looking like the end of the data. `widget.isLoadingMore`
              // stays as the catalog's way of previewing that state.
              state: widget.isLoadingMore || (_controller?.loadingMore ?? false)
                  ? ListFooterState.loadingMore
                  : ListFooterState.end,
              // Only when nothing is filtered. The label means "the whole collection is loaded, there
              // is no next page", and under a filtered list of three it read "all 101 of them", which
              // is a footer contradicting the header two lines above it. The section count already
              // states how many the filter matched, so there is nothing to replace it with.
              //
              // And only once there IS no next page: it used to be the row count, which is now a page
              // count, so a footer under the first thirty of a hundred would have claimed the whole
              // collection was loaded while the cursor said otherwise.
              totalLabel: _filter.isEmpty && !(_controller?.hasMore ?? false)
                  ? Lang.get('screens.products.all_of_them', {'count': _catalogueCount})
                  : null,
              // The row draws its own placeholder, so the two cannot drift.
              skeleton: const ProductRow.skeleton(),
            ),
          ],
        ),
    ];
  }

  Widget _row(ProductListItem item) {
    final (String primary, String? primaryUnit) = item.primaryFigure;
    final (String, String?)? remainder = item.remainderFigure;

    return ProductRow(
      name: item.name,
      // The open note joins the meta line rather than taking a line of its own: at
      // "2 poşet" the reader needs to know one pack is open, and a third line per row
      // would cost more vertical space than the fact is worth.
      meta: [?item.meta, ?item.openNote].join(' · '),
      amount: item.amount,
      formatted: primary,
      unit: primaryUnit,
      remainderFormatted: remainder?.$1,
      remainderUnit: remainder?.$2,
      expiryLabel: item.expiryLabel,
      daysUntilExpiry: item.daysUntilExpiry,
      parLevel: item.parLevel,
      // **The product detail screen was registered and unreachable.** `/products/:id` existed as a
      // route and nothing in the app navigated to it: tapping a product in the stock list did
      // nothing at all. That is D61's defect in its quietest form, because the screen is not
      // missing and the route is not missing, only the one line that joins them.
      //
      // The name stands in for the id while the app is fixture-backed, the same way the location
      // tree routes by path. The detail screen ignores the parameter today.
      // The server id when there is one, the name otherwise. A fixture row has never been
      // persisted, so the catalog keeps navigating by name exactly as it did.
      onTap: () => MagicRoute.to('/products/${item.id ?? Uri.encodeComponent(item.name)}'),
    );
  }
}
