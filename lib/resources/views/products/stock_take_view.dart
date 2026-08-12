import 'dart:async';

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart'
    show ButtonIntent, ButtonSize, MSBottomSheet, MSButton, MSInput, MagicStarterConfirmDialog;

import '../../../app/controllers/product_controller.dart';
import '../../../app/controllers/stock_take_controller.dart';
import '../../../app/support/count_progress.dart';
import '../../../app/support/plural.dart';
import '../../../ui/layouts/app_page_scaffold.dart';

import '../../../ui/components/count_row/count_row.dart';
import '../../../ui/components/list_footer/list_footer.dart';
import '../../../ui/components/option_row/option_row.dart';
import '../../../ui/components/section_card/section_card.dart';
import 'count_fixtures.dart';
import 'count_line.dart';
import 'product_filter_sheet.dart' show FilterOption;
import 'product_fixtures.dart';

/// Counting one location, and turning what was found into ledger entries.
///
/// ### A count states an absolute; the ledger stores deltas
///
/// The user types what is on the shelf. The app writes the difference, with reason
/// `stock_take` and NOT `correction` (D59): `data-model.md` separates them deliberately, as
/// "a counted correction after a physical count" against "fixing a data-entry error". Folding
/// a count into `correction` would destroy the ability to tell shrinkage from a typo, which is
/// the same distinction that keeps `waste` out of `consumption`.
///
/// Because the ledger takes deltas, the screen has to show both numbers: what was counted and
/// what that implies as a change. A user who types 1 and later finds a `-500 ml` movement they
/// never asked for has been surprised by their own stock take.
///
/// ### Blind until counted (D58)
///
/// No expected figure appears next to an uncounted row. Warehouse practice calls this a blind
/// count and the reason is anchoring: a counter shown "5" looks at a shelf and sees five. The
/// moment a number is entered the system figure and the difference appear, so a discrepancy is
/// diagnosable while the user is still in front of the shelf. Blind while counting, informed
/// immediately after.
///
/// ### Uncounted and zero are different facts
///
/// An empty field means nobody looked; it is left completely alone at commit. A zero writes the
/// whole balance off. The placeholder is a dash for that reason, and the summary states both
/// counts so the user can see what they are NOT changing.
///
/// ### A match writes nothing
///
/// Counting and finding agreement is not a movement. Writing zero-delta rows would record
/// non-events, and it would do measurable harm: `movementCount` decides a product's forecast
/// tier, so counts would promote products into "we can forecast this" without any consumption
/// behind it.
///
/// ### Every counted row is submitted, not only the ones that disagree
///
/// The expected figures come from a list that was loaded some seconds ago, so "this row matches"
/// is the client's opinion about a balance that may have moved. The server recomputes the
/// difference against the live ledger and answers per row, which makes a stale expected harmless:
/// a row the screen believed was fine still gets checked. The button's count is a prediction and
/// the toast afterwards is the measurement, which is why the two can legitimately differ.
///
/// ### A surplus with nothing to date it stays unfinished, here
///
/// Finding MORE than the record is inbound stock, and inbound stock needs a batch, and a batch
/// carries a date this screen never asks for. When there is a sealed batch at the location the
/// surplus joins it and inherits its date; when there is not, the server writes nothing and says
/// so, and the row stays visible with what it needs. Stock entry owns it from there, because that
/// screen shows the date it inferred and lets the user change it in one tap.
///
/// ### The lines are what the record claims is here
///
/// A count checks a claim, so the rows are the products the ledger says sit at this location.
/// Discovering stock the record has never seen is what scanning and receipt capture are for, and
/// offering the whole catalogue at every shelf would make a forty-row count a four-hundred-row one.
/// Serial-tracked products are left out for a different reason: their quantity IS the count of
/// their units, so they are counted by reading units rather than by typing a number.
@immutable
class StockTakeView extends StatefulWidget {
  /// The lines to count, supplied by the caller, which is how the preview catalog stays offline.
  ///
  /// Null means "read [ProductController]", which is what the route does. The preview passes
  /// [fridgeCount] instead, and that is not a second fixture inside a wired screen: it is the same
  /// contract filled from a different source, and the only way the catalog can render this screen
  /// with no backend and no authenticated tenant behind it.
  final List<CountLine>? lines;

  /// Creates the [StockTakeView], reading from [ProductController].
  const StockTakeView({super.key, this.lines});

  @override
  State<StockTakeView> createState() => _StockTakeViewState();
}

class _StockTakeViewState extends State<StockTakeView> {
  static const IconData _saveIcon = Icons.playlist_add_check;
  static const IconData _searchIcon = Icons.search_outlined;
  static const IconData _changeIcon = Icons.unfold_more;
  static const IconData _leaveIcon = Icons.check;

  /// Created in [initState] rather than read through a getter, because `Magic.findOrPut`
  /// INSTANTIATES on first read and the controller loads in `onInit`: a getter would fire a request
  /// from the catalog the moment this screen was previewed.
  StockTakeController? _controller;

  /// The products list, read only for the location chips and which of them hold stock.
  ProductController? _catalogue;

  /// How long after the last keystroke the shelf is narrowed.
  ///
  /// Longer than the browse list's 350ms, because this field is used while holding a product: the
  /// user types a few letters, looks at the shelf, then types more. A tighter window would fire
  /// mid-word and reflow the sheet under their thumb.
  static const Duration _searchDelay = Duration(milliseconds: 400);

  /// How close to the bottom, in logical pixels, the next page of the shelf is asked for.
  static const double _loadMoreThreshold = 240;

  final TextEditingController _search = TextEditingController();

  Timer? _searchDebounce;

  /// The scroll the shell put above this page, watched for the bottom of the sheet.
  ///
  /// The scrollable is an ANCESTOR, so a `NotificationListener` among these children would never
  /// fire; `Scrollable.maybeOf` looks the direction the widget actually lies in. Same shape as the
  /// products list, and the same reason.
  ScrollPosition? _scroll;

  /// Which location is being counted, empty until [_activeLocation] names one.
  ///
  /// A count is always scoped to one place, because that is how a person does it: you stand in
  /// front of one shelf.
  String _locationId = '';

  /// Counts as typed, keyed by product. Absent means uncounted, which is why this is a map with
  /// holes rather than a list of zeroes.
  final Map<String, num?> _whole = <String, num?>{};
  final Map<String, num?> _inner = <String, num?>{};

  /// The rows the last commit could not finish, keyed the same way.
  ///
  /// Only the unfinished ones are kept. A row that landed has nothing left to say, and holding its
  /// outcome would leave a stale answer beside a freshly reloaded expected figure.
  final Map<String, CountResult> _unfinished = <String, CountResult>{};

  /// What each committed row was counted as, keyed the same way, for this shelf and this visit.
  ///
  /// **A committed row used to lose its typed figure and read as "Not counted" again.** The comment
  /// justifying that cited D58's blind count, and the reasoning was right about the wrong thing: D58
  /// keeps a row blind until it is COUNTED, and these rows have been counted. Clearing them made the
  /// screen appear to undo the user's work, which is exactly what Anılcan saw after confirming five
  /// rows and reading `0 recorded`.
  ///
  /// Held in their own maps rather than left in [_whole] and [_inner], and that separation is what
  /// keeps the next commit honest: a commit sends what is CURRENTLY typed, so a settled row cannot be
  /// submitted twice, and re-typing one puts it back into the live maps and submits it again.
  final Map<String, num?> _settledWhole = <String, num?>{};
  final Map<String, num?> _settledInner = <String, num?>{};

  /// What the server did with each committed row, so a restored row can say so.
  final Map<String, CountResult> _settled = <String, CountResult>{};

  /// The ROW behind every figure typed on this shelf, keyed the same way as the figures.
  ///
  /// **Without this the sheet can only commit what is currently on screen.** A count is a product,
  /// an expected quantity and a number; [_whole] and [_inner] hold the number alone, and the other
  /// two came from whichever rows the controller had loaded. Narrow the shelf with a search and
  /// those rows are gone, so a figure typed a moment earlier had nothing left to attach to.
  ///
  /// Kept as the row rather than as the ids to re-fetch, because a commit must not depend on a
  /// request succeeding: the numbers are already in the user's head and on their shelf, and asking
  /// the server again to find out what they were counting would put a network failure between a
  /// finished count and saving it.
  ///
  /// Cleared with the rest of the per-shelf state when the shelf changes, for the same reason those
  /// are: a row typed for the fridge must never commit against the pantry.
  final Map<String, CountLine> _touched = <String, CountLine>{};

  /// Whether the committed rows are being shown again.
  ///
  /// They leave the sheet when they land, because on a shelf of a thousand the only thing that
  /// matters is what is LEFT. The bar above the list is what makes that reversible rather than
  /// destructive: a user who wants to check the number they entered gets it back in one tap.
  bool _showSettled = false;

  /// Whether a commit is in flight, so the button cannot be pressed twice.
  bool _saving = false;

  @override
  void initState() {
    super.initState();

    if (widget.lines == null) {
      // Two controllers, because there are two questions. The catalogue answers which locations
      // exist and which hold anything; the shelf answers what the record says is on the one being
      // counted. Only the second is this screen's own.
      final ProductController catalogue = ProductController.instance
        ..addListener(_onControllerChanged);

      // **`onInit` has to be called here, and nothing else calls it.** `Magic.findOrPut` only
      // registers the instance, and the framework's only caller of `onInit` is `MagicView`, which
      // this screen is not. Guarded on `initialized` because the controller is keyed by type and
      // outlives this screen, so a second visit would otherwise refetch on every navigation.
      if (!catalogue.initialized) catalogue.onInit();

      _catalogue = catalogue;
      _controller = StockTakeController.instance..addListener(_onControllerChanged);

      // Seeded ONCE, here, and not in `didChangeDependencies`, which is where it was.
      //
      // **That was a clobber waiting for a keyboard.** The field is debounced by 400ms, so during
      // that window it holds what the user just typed while `controller.query` still holds the
      // previous term. `didChangeDependencies` fires on any inherited change, and on a phone the
      // loudest one is `MediaQuery` when the keyboard opens or closes: exactly while someone is
      // typing. It would have overwritten the input with the stale query and silently undone the
      // last few characters.
      //
      // `initState` cannot race it: the `State` is new, `_search` is empty, and the only thing in
      // the controller is whatever a previous visit left there, which is precisely what this is for.
      _syncSearchField();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final ScrollPosition? position =
        _controller == null ? null : Scrollable.maybeOf(context)?.position;

    if (position == _scroll) return;

    _scroll?.removeListener(_onScroll);
    _scroll = position;
    _scroll?.addListener(_onScroll);
  }

  /// Seeds the field from the shelf it is narrowing, once per mount.
  ///
  /// **The controller outlives this screen and the field does not.** `StockTakeController` is keyed
  /// by type, so leaving the count screen and coming back gives a fresh `State` with an empty input
  /// while the controller still holds the previous query: the sheet came back narrowed to four rows
  /// with nothing on screen saying why. Measured by navigating away and back after searching.
  ///
  /// Seeded rather than cleared, because the search is the user's and a quick trip to another screen
  /// is not a reason to throw it away. Called from [initState] and nowhere else, so it cannot fire
  /// mid-edit; the guard on inequality stays because it costs nothing and says what it means.
  void _syncSearchField() {
    final StockTakeController? controller = _controller;

    if (controller == null) return;
    if (_search.text == controller.query) return;

    _search.text = controller.query;
  }

  /// Asks for the next page of the shelf as its bottom comes into reach.
  void _onScroll() {
    final ScrollPosition? position = _scroll;

    if (position == null || !position.hasContentDimensions) return;

    if (position.maxScrollExtent - position.pixels <= _loadMoreThreshold) {
      _controller?.loadMore();
    }
  }

  /// Debounces a keystroke into a shelf search.
  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(_searchDelay, () {
      if (mounted) _controller?.search(value);
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _search.dispose();
    _scroll?.removeListener(_onScroll);
    _controller?.removeListener(_onControllerChanged);
    _catalogue?.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  /// The locations offered as chips, in the endpoint's reading order.
  List<FilterOption> get _locationOptions => _catalogue?.locations ?? locationOptions;

  /// The location being counted.
  ///
  /// Resolved here rather than assigned in [initState], because the tenant's locations arrive with
  /// the first load and a default written into state before then would stick.
  String get _activeLocation {
    if (_locationId.isNotEmpty) return _locationId;

    // The preview's fixture lines are all the fridge's, so it names the fridge.
    if (widget.lines != null) return 'loc-fridge';

    final List<FilterOption> options = _locationOptions;

    if (options.isEmpty) return '';

    // **The first location HOLDING something, not simply the first.** Locations arrive in the tree's
    // reading order, so the first one is a root, and a root holds nothing directly: its children do.
    // Measured against the demo tenant, whose first location has no stock at all, defaulting to it
    // opened this screen on "nothing at this location" for a tenant with four full shelves, which
    // reads as a broken screen rather than as an empty shelf.
    //
    // Answered from the LOCATION payload's own `stock_count` rather than by scanning products. The
    // products it could scan are one page now, so a full shelf whose rows sit on a later page would
    // have read as empty and the default would have moved to the wrong shelf. It is also the only
    // order that works: the shelf itself is fetched per location, so deciding which one to fetch
    // cannot depend on having fetched them all.
    final ProductController? catalogue = _catalogue;

    for (final FilterOption option in options) {
      if (catalogue == null || catalogue.holdsStock(option.id)) return option.id;
    }

    return options.first.id;
  }

  /// Makes sure the shelf being counted has been fetched.
  ///
  /// Called from `build` rather than from `initState`, because the location is not known there: the
  /// tenant's locations arrive with the first load, and [_activeLocation] resolves against them. The
  /// controller drops a repeat call for a location it already holds or is already fetching, so
  /// calling this on every frame issues at most one request per shelf.
  void _syncShelf() {
    final StockTakeController? controller = _controller;
    final String locationId = _activeLocation;

    if (controller == null || locationId.isEmpty) return;

    // **The failure guard is per SHELF, not global.** It read `controller.failed` alone, so one
    // failed shelf froze the screen: picking any other chip changed `_locationId` and this returned
    // early anyway, leaving the error panel over a location that had never been tried. A failure
    // only blocks a retry of the shelf it happened on, and the retry button forces that one.
    if (controller.locationId == locationId) return;

    // After the frame, because `open` notifies listeners and this runs during a build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) controller.open(locationId);
    });
  }

  /// How a line is keyed in the typed-count maps.
  ///
  /// The product id when there is one, which there is on real data. Keying by NAME was the original
  /// shape and it is a defect waiting for two products to share a name: one row's count would write
  /// itself onto the other. Fixtures carry no id, so they keep the name.
  String _keyOf(CountLine line) => line.product.id ?? line.product.name;

  /// The lines for the chosen location, with any typed counts folded in.
  /// The lines on the sheet, with anything typed folded in and anything settled taken out.
  ///
  /// A settled row leaves unless [_showSettled] brought it back, and when it comes back it comes
  /// back with the figure that was entered rather than as a blank row: the point of showing it again
  /// is checking what was counted.
  List<CountLine> get _lines => (widget.lines ?? _fromController())
      .where((line) => _showSettled || !_isSettled(line))
      .map(
        (line) => CountLine(
          product: line.product,
          expected: line.expected,
          countedWhole: _typed(_whole, _settledWhole, line) ?? line.countedWhole,
          countedRemainder: _typed(_inner, _settledInner, line) ?? line.countedRemainder,
        ),
      )
      .toList();

  /// Whether this row is committed AND not being re-typed.
  ///
  /// **The second half is what stops a correction from vanishing.** `_settled` alone was the test, so
  /// restoring a saved row, typing a new number and hiding again dropped that number three ways at
  /// once: the row left the sheet, the verdict still read `Counted · matched`, and `countedLines`
  /// excluded it, so the correction was never submitted. Silently: no error, and the figure sat in
  /// `_whole` where nothing would ever read it.
  ///
  /// A live typed value therefore outranks a settled one everywhere, which is the same precedence
  /// [_typed] already applies to the FIGURE. Re-typing a saved row is how a user corrects a count
  /// they have already written, and a correction has to behave like any other uncommitted count.
  bool _isSettled(CountLine line) {
    final String key = _keyOf(line);

    if (!_settled.containsKey(key)) return false;

    return !_whole.containsKey(key) && !_inner.containsKey(key);
  }

  /// What is in the live map for this row, or in the settled one when it has been committed.
  ///
  /// The live map wins, because re-typing a settled row is how a user corrects a count they have
  /// already saved, and the correction has to be what shows and what submits.
  num? _typed(Map<String, num?> live, Map<String, num?> settled, CountLine line) {
    final String key = _keyOf(line);

    if (live.containsKey(key)) return live[key];

    return settled[key];
  }

  /// Every row typed into on this shelf during this visit, whatever the search is showing now.
  ///
  /// **The screen used to answer this from the rows on screen, and a search empties those.** Typing
  /// a count for one product and then searching for the next left the first product out of the
  /// loaded page, so the summary fell to `0 counted`, the commit button went dead, and the work
  /// already done could not be saved at all. The figures were never lost, they sat in [_whole] and
  /// [_inner] the whole time, but nothing read them: for the user that is the same thing as losing
  /// them, and worse, because the screen said zero rather than saying nothing.
  ///
  /// So the typed maps are the source, and [_touched] is what makes that possible: a figure alone
  /// cannot be committed, since the commit needs the product and its expected quantity to compute a
  /// delta, and those live on the row. Recording the row when it is first typed into keeps the whole
  /// visit addressable no matter which page the shelf is scrolled or filtered to.
  ///
  /// Committed rows fall out on their own, because a commit moves their figures from [_whole] and
  /// [_inner] into the settled maps.
  List<CountLine> _countedThisVisit() {
    final List<CountLine> out = <CountLine>[];

    // In the order the rows were first typed into, which is the order the user worked in and so the
    // order the confirmation dialog should list them in.
    for (final MapEntry<String, CountLine> entry in _touched.entries) {
      final String key = entry.key;

      if (!_whole.containsKey(key) && !_inner.containsKey(key)) continue;

      out.add(
        CountLine(
          product: entry.value.product,
          expected: entry.value.expected,
          countedWhole: _whole[key],
          countedRemainder: _inner[key],
        ),
      );
    }

    return out;
  }

  /// How many rows on this shelf have been counted, settled ones included.
  ///
  /// **Not the rows with a typed value, which is what it used to be.** A committed row has no live
  /// figure any more, so counting only those made the header fall back to zero the moment a commit
  /// landed: five rows counted, header `0 of 25`.
  int _countedTotal() {
    final Set<String> counted = <String>{..._settled.keys};

    for (final CountLine line in _countedThisVisit()) {
      if (line.isCounted) counted.add(_keyOf(line));
    }

    return counted.length;
  }

  /// The products the record says sit at one location, and that can be counted by typing a number.
  ///
  /// Serial-tracked products are left out because their quantity IS the count of their units, so a
  /// typed figure would be a second, disagreeing answer to "how many". The server refuses them too,
  /// which is the guard rather than the duplicate: this keeps a row that can only ever be refused
  /// off the sheet.
  /// **The whole shelf, not the browse list's current page.** This read `_controller.items`, which
  /// was the entire catalogue and is now one filtered page of thirty. Left alone it would have built
  /// a count sheet from whatever the user happened to have scrolled to: short, with nothing on
  /// screen saying so, and every product past the page silently keeping its old balance. On a ledger
  /// that is the worst available shape of bug, because the user believes the count landed.
  ///
  /// [StockTakeController] fetches it a page at a time, and [_syncShelf] is what asks for it.
  ///
  /// **A page is safe here where it was not before**, and the reason is worth keeping next to the
  /// code: an uncounted row writes NOTHING, and the commit sends only what was typed, so a row the
  /// user never scrolled to is a row left exactly as it was. The header counts against the shelf's
  /// real total rather than the loaded rows, so nobody is told they are nearly done fifty rows into
  /// a thousand. What was unsafe before was a sheet built from the BROWSE list's page, which looked
  /// like the whole shelf and was a slice of a different list.
  List<ProductListItem> _stockedAt(String locationId) {
    if (locationId.isEmpty) return const <ProductListItem>[];

    return <ProductListItem>[
      for (final ProductListItem product in _controller?.rows ?? const <ProductListItem>[])
        if (product.locationIds.contains(locationId) && product.tracking != TrackingMode.serial)
          product,
    ];
  }

  /// What the record claims sits at the location being counted.
  List<CountLine> _fromController() {
    final String locationId = _activeLocation;

    return <CountLine>[
      for (final ProductListItem product in _stockedAt(locationId))
        CountLine(product: product, expected: expectedAt(product, locationId)),
    ];
  }

  /// The full path of the location being counted, for the subtitle.
  String _pathOf(String id) {
    for (final FilterOption option in _locationOptions) {
      if (option.id == id) return option.fullPath;
    }

    return resolveLocationPath(id) ?? id;
  }

  @override
  Widget build(BuildContext context) {
    _syncShelf();

    final List<CountLine> lines = _lines;
    final int counted = _countedTotal();
    // **From the visit, not from the rows on screen.** A search narrows what is loaded, and reading
    // the variances off the visible rows made a count typed before the search invisible to the
    // summary, to the confirmation dialog and to the commit itself.
    final List<CountLine> variances = _countedThisVisit()
        .where((l) => l.isCounted && !l.isMatched)
        .toList();
    final StockTakeController? controller = _controller;
    final String locationId = _activeLocation;

    // Two fetches stand between this screen and its sheet: the locations, and then the shelf itself.
    // Reading only one status would call the screen loaded while the shelf was still coming, and an
    // empty sheet at that moment reads as "nothing at this location" for a shelf that is full.
    final bool loading = controller != null &&
        (controller.isLoading ||
            (_catalogue?.isLoading ?? false) ||
            (controller.locationId != locationId && !controller.failed));
    final bool failed =
        controller != null && (controller.failed || (_catalogue?.isError ?? false));

    // The commit is the point of this screen and it used to sit at the END of the count, so a
    // forty-line shelf put `Sayımı kaydet` a full scroll away from the last line the user typed.
    // Pinned, it is where the user's thumb already is when they finish.
    return AppPageScaffold(
      title: Lang.get('screens.stock_take.title'),
      // Suppressed while loading, for the same reason the products list suppresses its own: the
      // counted-of-total figure is genuinely unknown then, and "0 / 0" beside a real shelf name
      // reads as an empty shelf rather than as a pending request.
      subtitle: loading
          ? null
          : Lang.get('screens.stock_take.subtitle', {
              'location': _pathOf(_activeLocation),
              'counted': counted,
              // The SHELF's size, not the loaded rows. With a page of fifty and a shelf of a
              // thousand, `0 / 50 counted` would tell a user they were nearly done fifty rows in.
              // The server answers the real figure whether or not the client has scrolled to it.
              'total': _shelfTotal(lines),
            }),
      // **This screen had no exit, and that was found by looking at it rather than by reading it.**
      // It passed neither of these, and its only button was wired to `() {}` whenever the count came
      // out perfect, so a user who counted a whole shelf and found every number right was stuck: the
      // button said "Sayımı bitir" and did nothing, and there was no back affordance either. Every
      // sibling screen passes this pair; this one was the exception.
      backLabel: Lang.get('screens.stock_take.back'),
      backFallback: '/',
      footer: _buildCommit(context, lines, counted, variances),
      children: [
        _buildLocation(),
        if (!loading && !failed && _settled.isNotEmpty) _buildSettledBar(),
        if (loading)
          _buildLoading()
        else if (failed)
          _buildLoadFailed()
        else if (lines.isEmpty)
          _buildNothingHere()
        else
          _buildLines(lines),
      ],
    );
  }

  /// Which shelf. Chips rather than a tree, because a count is scoped to one leaf and the
  /// tree's job (finding a place to put something) is not this screen's job.
  /// Which shelf is being counted, as one row rather than as a wall of chips.
  ///
  /// **Measured: the chip wall was 235 logical px at 390x844, 28 per cent of the screen, for a
  /// control the user touches once per shelf.** The list it pushed down is the reason the screen
  /// exists. Worse, the arithmetic said the real cost only shows up with a keyboard: the count list
  /// began at y=621 on an 844px screen, so any keyboard taller than 223px put every row off screen,
  /// and every phone keyboard is far above that. Searching a shelf while seeing it was impossible.
  ///
  /// Collapsed, this is 44px and the shelf name stays on screen, which is the part that has to
  /// survive: a count committed against the wrong shelf is a ledger entry, not a typo.
  Widget _buildLocation() {
    final String active = _activeLocation;

    return WAnchor(
      onTap: _pickLocation,
      semanticLabel: Lang.get('screens.stock_take.change_location', {'path': _pathOf(active)}),
      child: WDiv(
        // Card tone plus a hairline, never `bg-surface-container-high`: that token is DESIGN.md's
        // INPUT background and reads as recessed in light mode, which is the universal look of a
        // disabled control. Elevation direction flips between appearances, so only a border can
        // carry "pressable" in both.
        className: 'flex flex-row items-center gap-3 min-h-11 px-4 py-2 rounded-lg '
            'bg-surface-container border border-color-border',
        children: [
          WText(
            Lang.get('screens.stock_take.where_group'),
            className: 'text-xs font-medium text-fg-muted shrink-0',
          ),
          // `flex-1 min-w-0` beside `truncate`, because `truncate` alone only sets the overflow
          // behaviour: without a shrinkable box the Text keeps its intrinsic width and the ellipsis
          // never appears. A deep path is exactly the case that needs it.
          WText(
            _pathOf(active),
            className: 'flex-1 min-w-0 truncate text-sm font-medium text-fg',
          ),
          const WIcon(_changeIcon, className: 'size-4 text-fg-muted shrink-0'),
        ],
      ),
    );
  }

  /// Opens the shelf picker and switches to what it returns.
  ///
  /// A sheet rather than the chips inline, because the choice is made once and the screen belongs
  /// to the count. `OptionRow` is the same picker row the move sheet uses, so a location list looks
  /// the same wherever it is offered.
  Future<void> _pickLocation() async {
    final String? picked = await MSBottomSheet.show<String>(
      context,
      title: Lang.get('screens.stock_take.pick_location_title'),
      // **The `Builder` is load-bearing, and leaving it out is not a style slip.** The sibling
      // sheets pop with `Navigator.of(context)` from inside their own `build`, so their context
      // already sits under the sheet's route. This body is built inline from the VIEW's context,
      // which resolves to the route BEHIND the sheet: tapping an option popped the count screen
      // instead of the sheet, and the app threw a navigator assertion, a go_router delegate
      // assertion and a duplicate GlobalKey in one go.
      body: Builder(
        builder: (BuildContext sheetContext) => WDiv(
          className: 'flex flex-col gap-1',
          children: [
            for (final FilterOption option in _locationOptions)
              OptionRow(
                label: option.fullPath,
                isSelected: option.id == _activeLocation,
                semanticLabel: option.id == _activeLocation
                    ? Lang.get('screens.stock_take.current_location', {'path': option.fullPath})
                    : Lang.get('screens.stock_take.pick_location', {'path': option.fullPath}),
                onTap: () => Navigator.of(sheetContext).pop(option.id),
              ),
          ],
        ),
      ),
    );

    // **Against the RESOLVED shelf, not the raw field.** `_locationId` is empty until the user picks
    // one, while `_activeLocation` has already resolved to the first shelf holding stock, so on the
    // shelf the screen opens on the two disagree. Comparing the raw field there made "pick the shelf
    // I am already counting" run the whole reset: typed figures, settled rows and the search, gone
    // for a gesture that changed nothing.
    if (picked == null || !mounted || picked == _activeLocation) return;

    setState(() {
      _locationId = picked;
      // The controller resets its own query when a shelf opens, so the field has to go with it.
      // Left alone it showed a term that was no longer narrowing anything, which is the same
      // field-and-state desync the products list had.
      _searchDebounce?.cancel();
      _search.clear();
      // Another shelf is another count. Carrying the typed figures across would let a number
      // entered for the fridge commit itself against the pantry's balance.
      _whole.clear();
      _inner.clear();
      _touched.clear();
      _unfinished.clear();
      // **And the settled state, which is per SHELF and was leaking across them.** Its own docblock
      // says "this shelf and this visit" and nothing enforced it: the bar went on reporting the
      // previous shelf's saved rows, and a product that sits at two locations was hidden on the
      // second one, so a row that still needed counting was invisible there.
      _settled.clear();
      _settledWhole.clear();
      _settledInner.clear();
      _showSettled = false;
    });
  }

  /// The sheet itself.
  /// How many products the record says are on this shelf, matching the search.
  ///
  /// The controller's total on a wired screen; the rendered rows in the preview, which has no
  /// server and where the two are the same number anyway.
  int _shelfTotal(List<CountLine> lines) => _controller?.total ?? lines.length;

  /// Finding one product on a shelf of a thousand, without scrolling to it.
  ///
  /// **Server-side, like the products list, and for the same reason.** A search over the loaded
  /// page could only find what the user had already scrolled past, which on a count sheet is the
  /// opposite of useful: the row you are hunting for is the one you have not reached.
  /// What has been saved on this shelf, and the way back to it.
  ///
  /// **The bar is what makes hiding a settled row reversible rather than destructive.** Rows leave
  /// the sheet when they land, because on a long shelf the only thing that matters is what is left;
  /// a user who wants to check the figure they entered gets it back in one tap, and the count they
  /// see is the one they typed rather than a blank row.
  Widget _buildSettledBar() {
    final int matched = _settled.values
        .where((r) => r.outcome != CountOutcome.written)
        .length;
    final int written = _settled.values
        .where((r) => r.outcome == CountOutcome.written)
        .length;

    return WDiv(
      // `rounded-lg` and `px-4 py-3`, which are `Callout`'s own base and `SectionCard`'s rhythm.
      // It was `rounded-md px-3 py-2` and that disagreed with every card it sits between: DESIGN.md
      // asks for concentric corners, and a 12px radius beside a 16px one reads as a different kind
      // of thing rather than as a sibling.
      //
      // Card tone plus a hairline rather than a fill, because elevation direction inverts between
      // appearances and no fill can mean "pressable" in both.
      //
      // Not a `Callout`, and that was checked rather than assumed: it covers title + message +
      // action, but it stacks the action UNDER the message, which turns a two-line state into a
      // four-line box. Its geometry is borrowed so the two still read as the same material.
      className:
          'flex flex-row items-center justify-between gap-3 px-4 py-3 rounded-lg '
          'bg-surface-container border border-color-border',
      children: [
        WDiv(
          className: 'flex flex-col gap-0.5 flex-1 min-w-0',
          children: [
            // Nominal, not imperative: this states what happened rather than asking for anything,
            // which is what `flutter-app.md` says a state reads like.
            WText(
              plural('screens.stock_take.settled', _settled.length, {'count': _settled.length}),
              className: 'text-sm text-fg',
            ),
            // **The detail line is the same honest pair the toast states**, and it is why the box
            // earns its height: `2 rows saved` alone left a wide strip with nothing in the middle.
            // A matching count writes nothing by design (D59), so the two numbers differ routinely
            // and stating only one of them is what made a whole shelf of confirmations read as `0`.
            // **One key holding both clauses, not two joined in Dart.** The first draft concatenated
            // two translated strings with a ` · ` in between, which breaks `flutter-app.md`'s rule
            // that interpolation goes through `:placeholder` and never through concatenation: the
            // separator would have been punctuation no translator could move, and the clause order
            // would have been fixed in code. The pair is keyed on the WRITTEN count, which is the
            // only clause that inflects, because `matched` is a participle and agrees with nothing.
            WText(
              plural('screens.stock_take.settled_detail', written, {
                'matched': matched,
                'written': written,
              }),
              className: 'text-xs text-fg-muted',
            ),
          ],
        ),
        MSButton(
          onPressed: () => setState(() => _showSettled = !_showSettled),
          intent: ButtonIntent.ghost,
          size: ButtonSize.sm,
          // `py-3.5` reaches the 44pt target on an `sm` button, where `py-3` lands at 40 and
          // `min-h-11` would grow the box without re-centring the label.
          className: 'py-3.5 axis-min shrink-0',
          child: WText(
            Lang.get(
              _showSettled ? 'screens.stock_take.settled_hide' : 'screens.stock_take.settled_show',
            ),
            // Muted like `FilterBar`'s own text actions, deliberately. That component records why:
            // a bright one beside a muted one reads as an accident rather than a hierarchy, and
            // these are the same kind of thing, a text action on the end of a row.
            className: 'text-sm font-medium text-fg-muted',
          ),
        ),
      ],
    );
  }

  /// The search field, which now lives in the pinned bar rather than in the page.
  ///
  /// **It moved to the bottom because that is where the keyboard is, and Apple says so.** The HIG
  /// (search fields, June 2026) is explicit: "Place search at the bottom if there's room... it keeps
  /// the search experience easy to reach", and when tapped it "animates into a search field above
  /// the keyboard so they can begin typing". Settings, Mail and Notes ship it. Here it is the
  /// difference between a usable count and an impossible one: with the field at the top of the page,
  /// the rows it filters were pushed under the keyboard, so the user typed a name and could not see
  /// the row they had just found.
  ///
  /// It shares the bar with the commit button, which is the Mail and Notes arrangement rather than
  /// the Settings one ("as a new toolbar where search is the only item"), because this screen's
  /// primary action has to stay in reach too.
  ///
  /// **`flex-1 min-w-0` is required here and was forbidden in the old position.** In the page's
  /// vertical children the shell hands unbounded height, so a flex child asserted and rendered
  /// nothing; inside a bounded Row it is what lets the field give the button its width.
  Widget _buildSearch() {
    return WDiv(
      className: 'flex-1 min-w-0',
      child: MSInput(
        // `h-11` on BOTH halves of the row, the fix the products list and the assistant composer
        // both needed: a field sized by its own padding measured 52 beside a 44 button, and
        // `items-center` centres that mismatch rather than hiding it.
        //
        // `bg-surface-container` rather than the `-high` the products list uses, because this one
        // sits on the footer's `bg-surface` fill: `-high` is the input tone for a page surface and
        // reads as recessed against a card.
        className: 'h-11 bg-surface-container',
        placeholder: Lang.get('screens.stock_take.search'),
        prefix: const WIcon(_searchIcon, className: 'size-4 text-fg-muted'),
        controller: _search,
        onChanged: _onSearchChanged,
      ),
    );
  }

  Widget _buildLines(List<CountLine> lines) {
    return SectionCard(
      label: Lang.get('screens.stock_take.list_group'),
      count: plural('screens.stock_take.product_count', _shelfTotal(lines), {'count': _shelfTotal(lines)}),
      children: [
        for (final CountLine line in lines)
          CountRow(
            name: line.product.name,
            unit: line.product.unit,
            // Only when the content unit is genuinely finer. A product whose base unit IS its
            // content unit (the demo tenant's milk: base `l`, content `1 l`) would otherwise get a
            // second field measuring the same thing in the same unit.
            remainderUnit: line.hasFinerContent ? line.product.contentUnit : null,
            counted: line.countedWhole?.toString(),
            countedRemainder: line.countedRemainder?.toString(),
            verdict: _verdictFor(line),
            state: _stateFor(line),
            // **Cleared means REMOVED, not stored as null**, and that became load-bearing when either
            // field started implying "counted": a lingering null key would keep a row counted after
            // the user emptied it, so the sheet would submit a figure nobody had typed.
            onChanged: (next) =>
                setState(() => _edit(line, () => _enter(_whole, _keyOf(line), next))),
            onDecrement: () => setState(
              () => _edit(line, () {
                final num current = line.countedWhole ?? 0;
                _whole[_keyOf(line)] = current <= 0 ? 0 : current - 1;
              }),
            ),
            onIncrement: () => setState(
              () => _edit(line, () => _whole[_keyOf(line)] = (line.countedWhole ?? 0) + 1),
            ),
            onRemainderChanged: (next) =>
                setState(() => _edit(line, () => _enter(_inner, _keyOf(line), next))),
            onConfirmRecorded: () => setState(() => _edit(line, () => _confirmRecorded(line))),
            // The figure the tap would write, through the SAME formatter the verdict uses, so the
            // button and the line under it can never state one quantity two ways. See the parameter's
            // own docblock for why this is the one place D58 lets the expected figure show.
            recordedFigure: line.figure(line.expected),
          ),
        // **A sheet that has more rows says so.** Without this the last loaded row looks like the
        // end of the shelf, and a user who stopped there would commit a count of the first page
        // believing it was the whole thing. The rows they never saw would be left alone either way,
        // which is what makes the pagination safe, but the belief would still be wrong.
        if (_controller != null)
          ListFooter(
            // `hasMore` alone covers both, because the cursor is only cleared once the last page
            // has landed: while that page is in flight `hasMore` is still true. A separate
            // `loadingMore` branch would have said the same thing twice.
            state: _controller!.hasMore ? ListFooterState.loadingMore : ListFooterState.end,
            totalLabel: _controller!.hasMore
                ? null
                : Lang.get('screens.stock_take.all_of_them', {'count': _shelfTotal(lines)}),
            skeleton: const CountRow.skeleton(),
          ),
      ],
    );
  }

  /// Fills a row with the quantity on record, in one tap.
  ///
  /// **The count stays blind until this is pressed** (D58), which is the whole reason it is a control
  /// rather than a pre-filled field: the expected figure appears because the user asked for it, not
  /// because the app assumed it. Agreeing is then their action, and a row nobody touched is still
  /// distinguishable from a row somebody checked and agreed with.
  ///
  /// Split the same way the two fields are, so a product with a finer content unit lands as whole
  /// units plus a remainder rather than as one decimal (D26): 1.5 cartons becomes 1 and 500 ml. The
  /// arithmetic mirrors `CountLine.countedTotal` in reverse, and `figure` is the read-only version of
  /// the same split, which is why both live on `CountLine`.
  void _confirmRecorded(CountLine line) {
    final String key = _keyOf(line);
    final num expected = line.expected;

    if (!line.hasFinerContent) {
      _whole[key] = expected;
      _inner.remove(key);

      return;
    }

    // `innerFor` rather than the arithmetic again. This file had its own copy of "multiply the
    // fraction by the content and round", which is the duplication this same change removed between
    // the count sheet and the detail screen, reintroduced one method away from it.
    final num inner = line.product.innerFor(expected) ?? 0;

    _whole[key] = expected.floor();

    // Absent rather than zero when the record holds no opened amount, because absence is what the
    // sheet reads as "this field was not answered" and a stored zero would claim it was.
    if (inner == 0) {
      _inner.remove(key);
    } else {
      _inner[key] = inner;
    }
  }

  /// Applies a change to one row's figures, recording the ROW first.
  ///
  /// **Every write to [_whole] or [_inner] goes through here, and that is the point.** The figure
  /// and the row it belongs to have to be recorded together or the commit cannot reconstruct what
  /// was counted once a search has scrolled the row out of the loaded page. Five call sites write
  /// figures (typing, either stepper button, the remainder field, and agreeing with the record), and
  /// a sixth that forgot to record the row would lose exactly one product's count, silently. Funnel
  /// them through one method and forgetting is not available.
  void _edit(CountLine line, VoidCallback change) {
    _touched[_keyOf(line)] = line;

    change();
  }

  /// Records a typed figure, or forgets the field when it no longer holds one.
  ///
  /// An unparseable or emptied field is ABSENT rather than null, because absence is what
  /// `CountLine` reads as uncounted (D58). Storing null would leave the key present, and with either
  /// field now implying a counted row that would submit a number the user had just deleted.
  void _enter(Map<String, num?> into, String key, String raw) {
    final num? value = num.tryParse(raw);

    if (value == null) {
      into.remove(key);

      return;
    }

    into[key] = value;
  }

  /// What the row says about itself, including what the last commit refused to write.
  String _verdictFor(CountLine line) {
    // A settled row says what happened to it rather than what it would do. Restoring one through the
    // bar is for checking a saved count, and `line.verdict` would describe a comparison against the
    // balance the commit has already corrected: a matched row would read as matched by luck rather
    // than as saved.
    final CountResult? landed = _isSettled(line) ? _settled[_keyOf(line)] : null;

    if (landed != null) {
      return landed.outcome == CountOutcome.written
          ? Lang.get('screens.stock_take.settled_written', {
              'delta': line.figure(landed.delta.abs()),
            })
          : Lang.get('screens.stock_take.settled_matched');
    }

    final CountResult? result = _unfinished[_keyOf(line)];

    if (result == null) return line.verdict;

    return switch (result.outcome) {
      // The number is the server's, not a recomputation of it: the surplus it could not place is
      // exactly what the user has to enter through stock entry.
      CountOutcome.needsDate => Lang.get('screens.stock_take.needs_date', {
        'amount': line.figure(result.delta.abs()),
      }),
      CountOutcome.serialTracked => Lang.get('screens.stock_take.serial_tracked'),
      _ => line.verdict,
    };
  }

  /// Uncounted, matched or a discrepancy. An unfinished row is a discrepancy: the shelf and the
  /// record still disagree, whatever the reason the difference could not be written.
  CountState _stateFor(CountLine line) {
    if (_unfinished.containsKey(_keyOf(line))) return CountState.variance;

    if (!line.isCounted) return CountState.uncounted;

    return line.isMatched ? CountState.matched : CountState.variance;
  }

  /// A shelf the record says holds nothing.
  Widget _buildNothingHere() {
    return SectionCard(
      label: Lang.get('screens.stock_take.list_group'),
      children: [
        WText(Lang.get('screens.stock_take.nothing_here'), className: 'text-sm text-fg-muted py-2'),
      ],
    );
  }

  /// The rows are on their way. Same component and same geometry as a real row, so the list cannot
  /// jump when the content lands.
  Widget _buildLoading() {
    return SectionCard(
      label: Lang.get('screens.stock_take.list_group'),
      children: [for (int i = 0; i < 3; i++) const CountRow.skeleton()],
    );
  }

  /// The request failed, which is not an empty shelf.
  Widget _buildLoadFailed() {
    return SectionCard(
      label: Lang.get('screens.stock_take.list_group'),
      error: Lang.get('screens.products.load_failed'),
      // Retries the SHELF as well, and forces it: a recorded failure is what stops `_syncShelf`
      // asking again on every frame, so without the force this button would clear nothing.
      onRetry: () {
        _catalogue?.load();
        _controller?.open(_activeLocation, force: true);
      },
      children: const <Widget>[],
    );
  }

  /// What committing will and will not do.
  Widget _buildCommit(
    BuildContext context,
    List<CountLine> lines,
    int counted,
    List<CountLine> variances,
  ) {
    // Both figures are arithmetic this screen reports about itself, and both shipped wrong in ways
    // nothing could see, so they live in `count_progress.dart` where a test can call the same code
    // rather than re-implement it.
    final int skipped = rowsLeftToCount(
      shelfTotal: _shelfTotal(lines),
      counted: counted,
      // The shelf total is the count matching the QUERY, and `counted` is now the whole visit, so
      // under a search the subtraction compares two different sets.
      searching: _controller?.query.isNotEmpty ?? false,
    );
    // **What gets committed is the whole visit, not the current page of it.** This read the rows on
    // screen, so counting a product and then searching for the next one emptied it: the summary said
    // `0 counted`, the button went dead, and there was no way to save work that had already been
    // done. `_countedThisVisit` holds only uncommitted figures already, so the settled filter that
    // used to be here is not needed: a commit moves a row's figures into the settled maps and it
    // drops out on its own.
    final List<CountLine> countedLines = _countedThisVisit()
        .where((l) => l.isCounted)
        .toList();

    // **The shelf is what says the count is over, not the button.** The screen used to leave for the
    // dashboard on any clean commit, so five rows of twenty-five ended the session. Every row on the
    // shelf being settled is the only thing that means finished, and the exit is offered here rather
    // than taken automatically: leaving is the user's call.
    final int total = _shelfTotal(lines);

    final bool finished = _controller != null &&
        shelfIsFinished(
          searching: _controller!.query.isNotEmpty,
          settled: _settled.length,
          shelfTotal: total,
          pendingCounts: countedLines.length,
        );

    if (finished) {
      return WDiv(
        className: 'flex flex-col gap-2 pb-2',
        children: [
          WText(
            Lang.get('screens.stock_take.shelf_done', {'total': total}),
            className: 'text-sm text-fg-muted',
          ),
          // The field stays even here, because finishing is not the only thing left to do: a user
          // who wants to re-check a row they entered gets to it by searching for it, and typing
          // takes the shelf out of the finished state on its own (`shelfIsFinished` is false while
          // a query narrows the sheet), which puts the normal bar back.
          WDiv(
            className: 'flex flex-row items-center gap-2',
            children: [
              _buildSearch(),
              MSButton(
                onPressed: () => MagicRoute.to('/'),
                className: 'h-11 justify-center shrink-0',
                child: WText(Lang.get('screens.stock_take.shelf_done_action')),
              ),
            ],
          ),
        ],
      );
    }

    return WDiv(
      className: 'flex flex-col gap-2 pb-2',
      children: [
        // Both numbers, because the second one is the one a user would not think to ask
        // about: the rows they skipped stay exactly as they were.
        WText(
          skipped == 0
              ? plural('screens.stock_take.summary', variances.length, {
                  'counted': counted,
                  'variances': variances.length,
                })
              : Lang.get('screens.stock_take.summary_skipped', {
                  'counted': counted,
                  'skipped': skipped,
                }),
          className: 'text-sm text-fg-muted',
        ),
        if (variances.isNotEmpty)
          WText(
            plural('screens.stock_take.will_write', variances.length, {'count': variances.length}),
            className: 'text-xs text-fg-muted',
          ),
        if (_unfinished.isNotEmpty)
          // Muted like its neighbours rather than tinted. The status families each name a specific
          // state (`expiring` a date, `low-stock` a threshold) and DESIGN.md's avoid list is explicit
          // that borrowing one for something it does not name misreads: "could not be finished" is
          // neither. The rows themselves already carry the discrepancy tone, and the toast carries
          // the urgency.
          WText(
            Lang.get('screens.stock_take.unfinished', {'count': _unfinished.length}),
            className: 'text-xs text-fg-muted',
          ),
        // **The search field and the commit share one bar, which is the whole point of the move.**
        // Apple's HIG offers both arrangements for bottom search: its own toolbar (Settings) or
        // alongside other controls (Mail, Notes). This screen takes the second, because a count has
        // one primary action and burying it to give search a bar of its own would trade one
        // out-of-reach control for another.
        WDiv(
          className: 'flex flex-row items-center gap-2',
          children: [
            _buildSearch(),
            MSButton(
          // **Committing asks first, and the question is the numbers.** This writes count movements
          // into an append-only ledger: undoing means writing a counter-movement, so the mistake
          // stays in the history forever even after it is fixed. The dialog restates what will be
          // written and, more importantly, what will NOT be: the skipped rows are left exactly as
          // they were, and that is the part a user cannot see from the list.
          //
          // A perfect count writes nothing, which `inventory-core.md` is explicit about ("A match
          // writes nothing", because a zero-delta row would buy a product a forecast tier it did not
          // earn). There is still something to send, because the server checks each row against the
          // live balance rather than trusting this screen's expected figure, so the confirmation is
          // skipped rather than the request.
          // **With nothing left to save the button becomes the way out, rather than dying.** It
          // read `Finish the count` and went disabled the moment a commit landed, so a user who
          // saved two rows of twenty-five was looking at a button promising an exit and refusing to
          // give one. This screen has had that defect before in another form, when the same button
          // was wired to an empty callback on a perfect count.
          //
          // One live action in the pinned bar at all times is what the bar is for, and the two jobs
          // never overlap: there is either something typed and unsaved, or there is not.
          disabled: _saving,
          onPressed: countedLines.isEmpty
              ? () => MagicRoute.to('/')
              : variances.isEmpty
              ? () => _commit(countedLines)
              : () => MagicStarterConfirmDialog.show(
                  context,
                  title: plural('screens.stock_take.commit_title', variances.length, {'count': variances.length}),
                  description: skipped == 0
                      ? plural('screens.stock_take.commit_description', variances.length, {
                          'count': variances.length,
                        })
                      : plural('screens.stock_take.commit_description_skipped', variances.length, {
                          'count': variances.length,
                        }),
                  confirmLabel: Lang.get('screens.stock_take.commit_confirm'),
                  onConfirm: () => _commit(countedLines),
                ),
              className: 'h-11 justify-center shrink-0',
              child: WDiv(
                className: 'flex flex-row items-center justify-center gap-2',
                children: [
                  // The glyph follows the job. A save icon over a button that navigates away would
                  // be the same lie the label was telling.
                  WIcon(
                    countedLines.isEmpty ? _leaveIcon : _saveIcon,
                    className: 'size-4',
                  ),
                  WText(
                    // `shelf_done_action` rather than a new string, and rather than `finish`. It
                    // names the NAVIGATION ("Back to overview") instead of claiming the count is
                    // over, which would be false with twenty-three rows still untouched. `finish`
                    // is unavailable here anyway: it is what the SAVE button says when every
                    // counted row matched.
                    countedLines.isEmpty
                        ? Lang.get('screens.stock_take.shelf_done_action')
                        : variances.isEmpty
                        ? Lang.get('screens.stock_take.finish')
                        : plural('screens.stock_take.save_variances', variances.length, {'count': variances.length}),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Send every counted row and act on what came back.
  Future<void> _commit(List<CountLine> countedLines) async {
    final StockTakeController? controller = _controller;

    // The preview has no controller and nothing to write to. It renders the same tree, which is the
    // point of it, so the button is real and its effect is simply absent.
    if (controller == null) return;

    final Map<String, num> counts = <String, num>{
      for (final CountLine line in countedLines)
        if (line.product.id != null && line.countedTotal != null)
          line.product.id!: line.countedTotal!,
    };

    if (counts.isEmpty) return;

    setState(() => _saving = true);

    final CountCommit commit = await controller.commit(_activeLocation, counts);

    if (!mounted) return;

    setState(() {
      _saving = false;
      _unfinished
        ..clear()
        ..addEntries(commit.unfinished.map((r) => MapEntry(r.productId, r)));

      // **A row that landed is SETTLED, not blind again.** This used to drop the typed figure
      // outright, citing D58, and D58 is about a row that has not been counted yet: these have been.
      // Dropping them made the screen appear to undo the work, which is what a user saw after
      // confirming five rows and reading `0 recorded`.
      //
      // Moved rather than kept, and the move is what stops a double submit: a commit sends what is
      // CURRENTLY typed, so a settled row is out of that set until the user re-types it.
      for (final CountResult result in commit.lines) {
        if (result.isUnfinished) continue;

        _settled[result.productId] = result;
        _settledWhole[result.productId] = _whole.remove(result.productId);
        _settledInner[result.productId] = _inner.remove(result.productId);
      }
    });

    if (commit.error != null) {
      MagicFeedback.error(Lang.get('screens.stock_take.title'), commit.error!);

      return;
    }

    if (commit.unfinished.isEmpty) {
      // **Two numbers, because they are two facts and only one of them was being reported.** The
      // toast said `:count recorded` and counted MOVEMENTS, so five rows confirmed against a correct
      // record read as `0 recorded`: true about the ledger, and a lie about the work. A matching
      // count writes nothing by design (D59), which is exactly why the row count has to be said out
      // loud beside it.
      MagicFeedback.success(
        Lang.get('screens.stock_take.title'),
        // **Two fragments and a wrapper, because both nouns inflect independently.** Keying one
        // string on `counted` left `:written changes written` wrong whenever the two counts differ,
        // which is the common case here: a matching count writes nothing, so five rows and zero
        // changes is normal. A single pipe can only ever be right about one of them.
        //
        // The wrapper is what keeps this inside the copy rule rather than concatenating in Dart: the
        // separator lives in the translation, so a translator can move it or reorder the clauses.
        Lang.get('screens.stock_take.committed_counted', {
          'rows': plural('screens.stock_take.committed_rows', commit.lines.length, {
            'counted': commit.lines.length,
          }),
          'changes': plural('screens.stock_take.committed_changes', commit.writtenCount, {
            'written': commit.writtenCount,
          }),
        }),
      );

      // **No navigation.** It used to leave for the dashboard on any clean commit, which ejected a
      // user who had counted five of twenty-five rows and left the other twenty untouched with
      // nothing saying so. The shelf decides when the count is over, and the exit is offered THERE:
      // see the footer's finished state.
      return;
    }

    // Stay on the screen. The unfinished rows are the only place the user can see WHICH they were,
    // and a toast on the way out would name a number and hide the exceptions behind it.
    MagicFeedback.error(
      Lang.get('screens.stock_take.title'),
      Lang.get('screens.stock_take.committed_partly', {
        'count': commit.writtenCount,
        'unfinished': commit.unfinished.length,
      }),
    );
  }
}
