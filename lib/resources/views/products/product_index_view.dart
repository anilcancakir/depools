import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart'
    show
        ButtonIntent,
        ButtonSize,
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
/// Rendered from [ProductController], and filtered client-side against the loaded rows, so
/// the sheet's count and the list cannot disagree. The preview catalog passes
/// [ProductIndexView.items] instead, which is the same contract from a different source.
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
  static const IconData _chevronIcon = Icons.chevron_right_outlined;

  ProductFilter _filter = const ProductFilter();

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
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  /// Every row the screen knows about, before the filter.
  List<ProductListItem> get _all =>
      widget.items ?? _controller?.items ?? const <ProductListItem>[];

  List<ProductListItem> get _visible => _all.where((item) => item.matches(_filter)).toList();

  int _countMatches(ProductFilter draft) => _all.where((item) => item.matches(draft)).length;

  /// The locations the filter sheet offers.
  ///
  /// From the controller when there is one, because a chip for a location this tenant does not
  /// have is a filter that can only ever match nothing.
  List<FilterOption> get _locationOptions => _controller?.locations ?? locationOptions;

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

  Future<void> _openSheet() async {
    final ProductFilter? applied = await ProductFilterSheet.show(
      context,
      initial: _filter,
      countMatches: _countMatches,
      locations: _locationOptions,
      categories: categoryOptions,
      tags: tagOptions,
    );

    // Null means dismissed, which is not the same as an empty filter. Coalescing the
    // two would silently clear a filter every time the user swiped the sheet away.
    if (applied == null || !mounted) return;
    setState(() => _filter = applied);
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
      subtitle: _isEmptyCatalogue || (_controller?.isLoading ?? false)
          ? null
          : Lang.get('screens.products.subtitle', {'team': _teamName, 'count': _all.length}),
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
          onPressed: () => MagicRoute.to('/urunler/yeni'),
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
            onChanged: (next) => setState(() => _filter = next),
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
            onChanged: (String _) {},
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
              onPressed: () => MagicRoute.to('/fis'),
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
                    onPressed: () => MagicRoute.to('/tara'),
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
                    onPressed: () => MagicRoute.to('/raf'),
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
                Lang.get('screens.products.filtered_description', {'count': _all.length}),
          ),
        ),
        MSButton(
          onPressed: () => setState(() => _filter = const ProductFilter()),
          fullWidth: true,
          className: 'justify-center',
          child: WText(Lang.get('screens.products.filter_clear')),
        ),
      ],
    );
  }

  /// The list, grouped so the thing that needs attention comes first.
  ///
  /// Expiring and out-of-stock items lead, because that is the one section a cafe
  /// opens this screen for daily and it needs no forecast to be correct, only a date
  /// comparison. The grouping is derived from [ProductListItem.needsAttention], the
  /// same test the three built-in saved filters cover, so the section and the chips
  /// cannot drift apart.
  ///
  /// **Both sections respect the filter.** An attention section that ignored it would
  /// keep showing an expired product after the user filtered to one location, which
  /// is exactly the "why is this still here" confusion the visible-filter rule exists
  /// to prevent.
  List<Widget> _buildList(List<ProductListItem> visible) {
    final List<ProductListItem> attention = visible.where((i) => i.needsAttention).toList();
    final List<ProductListItem> rest = visible.where((i) => !i.needsAttention).toList();

    return <Widget>[
      if (attention.isNotEmpty)
        SectionCard(
          label: Lang.get('screens.products.attention_group'),
          count: Lang.get('screens.products.product_count', {'count': attention.length}),
          // The only collapsible section on the screen. A cafe owner opens this screen
          // daily for exactly this list, so it starts open; once it is dealt with, the
          // whole block folds away instead of pushing the catalogue down the page. The
          // count stays visible closed, which is what keeps "3 ürün" actionable.
          collapsible: true,
          children: [for (final ProductListItem item in attention) _row(item)],
        ),
      if (rest.isNotEmpty)
        SectionCard(
          label: Lang.get('screens.products.all_group'),
          count: Lang.get('screens.products.product_count', {'count': rest.length}),
          action: MSButton(
            onPressed: () {},
            intent: ButtonIntent.ghost,
            size: ButtonSize.sm,
            className: 'py-3.5 axis-min',
            child: WDiv(
              className: 'flex flex-row items-center gap-0.5 axis-min',
              children: [
                WText(Lang.get('screens.products.all')),
                WIcon(_chevronIcon, className: 'size-4'),
              ],
            ),
          ),
          children: [
            for (final ProductListItem item in rest) _row(item),
            // The footer states the total rather than pretending to page eight fixtures.
            // The total is also the SKU count the plan meters on, so it is the one number
            // worth having at the bottom of this particular list.
            ListFooter(
              state: widget.isLoadingMore ? ListFooterState.loadingMore : ListFooterState.end,
              totalLabel: Lang.get('screens.products.all_of_them', {'count': _all.length}),
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
      // **The product detail screen was registered and unreachable.** `/urunler/:id` existed as a
      // route and nothing in the app navigated to it: tapping a product in the stock list did
      // nothing at all. That is D61's defect in its quietest form, because the screen is not
      // missing and the route is not missing, only the one line that joins them.
      //
      // The name stands in for the id while the app is fixture-backed, the same way the location
      // tree routes by path. The detail screen ignores the parameter today.
      // The server id when there is one, the name otherwise. A fixture row has never been
      // persisted, so the catalog keeps navigating by name exactly as it did.
      onTap: () => MagicRoute.to('/urunler/${item.id ?? Uri.encodeComponent(item.name)}'),
    );
  }
}
