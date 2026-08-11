import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart' show MSButton, MagicStarterConfirmDialog;

import '../../../app/controllers/product_controller.dart';
import '../../../ui/layouts/app_page_scaffold.dart';

import '../../../ui/components/choice_chip/choice_chip.dart';
import '../../../ui/components/count_row/count_row.dart';
import '../../../ui/components/section_card/section_card.dart';
import 'count_fixtures.dart';
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

  /// Created in [initState] rather than read through a getter, because `Magic.findOrPut`
  /// INSTANTIATES on first read and the controller loads in `onInit`: a getter would fire a request
  /// from the catalog the moment this screen was previewed.
  ProductController? _controller;

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

  /// Whether a commit is in flight, so the button cannot be pressed twice.
  bool _saving = false;

  @override
  void initState() {
    super.initState();

    if (widget.lines == null) {
      final ProductController controller = ProductController.instance
        ..addListener(_onControllerChanged);

      // **`onInit` has to be called here, and nothing else calls it.** `Magic.findOrPut` only
      // registers the instance, and the framework's only caller of `onInit` is `MagicView`, which
      // this screen is not. Guarded on `initialized` because the controller is keyed by type and
      // outlives this screen, so a second visit would otherwise refetch on every navigation.
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

  /// The locations offered as chips, in the endpoint's reading order.
  List<FilterOption> get _locationOptions => _controller?.locations ?? locationOptions;

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
    for (final FilterOption option in options) {
      if (_stockedAt(option.id).isNotEmpty) return option.id;
    }

    return options.first.id;
  }

  /// How a line is keyed in the typed-count maps.
  ///
  /// The product id when there is one, which there is on real data. Keying by NAME was the original
  /// shape and it is a defect waiting for two products to share a name: one row's count would write
  /// itself onto the other. Fixtures carry no id, so they keep the name.
  String _keyOf(CountLine line) => line.product.id ?? line.product.name;

  /// The lines for the chosen location, with any typed counts folded in.
  List<CountLine> get _lines => (widget.lines ?? _fromController())
      .map(
        (line) => CountLine(
          product: line.product,
          expected: line.expected,
          countedWhole: _whole.containsKey(_keyOf(line))
              ? _whole[_keyOf(line)]
              : line.countedWhole,
          countedRemainder: _inner.containsKey(_keyOf(line))
              ? _inner[_keyOf(line)]
              : line.countedRemainder,
        ),
      )
      .toList();

  /// The products the record says sit at one location, and that can be counted by typing a number.
  ///
  /// Serial-tracked products are left out because their quantity IS the count of their units, so a
  /// typed figure would be a second, disagreeing answer to "how many". The server refuses them too,
  /// which is the guard rather than the duplicate: this keeps a row that can only ever be refused
  /// off the sheet.
  List<ProductListItem> _stockedAt(String locationId) {
    if (locationId.isEmpty) return const <ProductListItem>[];

    return <ProductListItem>[
      for (final ProductListItem product in _controller?.items ?? const <ProductListItem>[])
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
    final List<CountLine> lines = _lines;
    final int counted = lines.where((l) => l.isCounted).length;
    final List<CountLine> variances = lines.where((l) => l.isCounted && !l.isMatched).toList();
    final bool loading = _controller?.isLoading ?? false;

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
              'total': lines.length,
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
        if (loading)
          _buildLoading()
        else if (_controller?.isError ?? false)
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
  Widget _buildLocation() {
    final String active = _activeLocation;

    return SectionCard(
      label: Lang.get('screens.stock_take.where_group'),
      children: [
        WDiv(
          className: 'flex flex-row wrap items-center gap-2 py-1',
          children: [
            for (final FilterOption option in _locationOptions)
              ChoiceChip(
                label: option.fullPath,
                isSuggested: option.id == active,
                semanticLabel: option.id == active
                    ? Lang.get('screens.stock_take.current_location', {'path': option.fullPath})
                    : Lang.get('screens.stock_take.pick_location', {'path': option.fullPath}),
                onTap: () => setState(() {
                  _locationId = option.id;
                  // Another shelf is another count. Carrying the typed figures across would let a
                  // number entered for the fridge commit itself against the pantry's balance.
                  _whole.clear();
                  _inner.clear();
                  _unfinished.clear();
                }),
              ),
          ],
        ),
      ],
    );
  }

  /// The sheet itself.
  Widget _buildLines(List<CountLine> lines) {
    return SectionCard(
      label: Lang.get('screens.stock_take.list_group'),
      count: Lang.get('screens.stock_take.product_count', {'count': lines.length}),
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
            onChanged: (next) => setState(() => _whole[_keyOf(line)] = num.tryParse(next)),
            onDecrement: () => setState(() {
              final num current = line.countedWhole ?? 0;
              _whole[_keyOf(line)] = current <= 0 ? 0 : current - 1;
            }),
            onIncrement: () =>
                setState(() => _whole[_keyOf(line)] = (line.countedWhole ?? 0) + 1),
            onRemainderChanged: (next) =>
                setState(() => _inner[_keyOf(line)] = num.tryParse(next)),
          ),
      ],
    );
  }

  /// What the row says about itself, including what the last commit refused to write.
  String _verdictFor(CountLine line) {
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
      onRetry: () => _controller?.load(),
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
    final int skipped = lines.length - counted;
    final List<CountLine> countedLines = lines.where((l) => l.isCounted).toList();

    return WDiv(
      className: 'flex flex-col gap-2 pb-2',
      children: [
        // Both numbers, because the second one is the one a user would not think to ask
        // about: the rows they skipped stay exactly as they were.
        WText(
          skipped == 0
              ? Lang.get('screens.stock_take.summary', {
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
            Lang.get('screens.stock_take.will_write', {'count': variances.length}),
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
          disabled: _saving || countedLines.isEmpty,
          onPressed: variances.isEmpty
              ? () => _commit(countedLines)
              : () => MagicStarterConfirmDialog.show(
                  context,
                  title: Lang.get('screens.stock_take.commit_title', {'count': variances.length}),
                  description: skipped == 0
                      ? Lang.get('screens.stock_take.commit_description', {
                          'count': variances.length,
                        })
                      : Lang.get('screens.stock_take.commit_description_skipped', {
                          'count': variances.length,
                          'skipped': skipped,
                        }),
                  confirmLabel: Lang.get('screens.stock_take.commit_confirm'),
                  onConfirm: () => _commit(countedLines),
                ),
          fullWidth: true,
          className: 'justify-center',
          child: WDiv(
            className: 'flex flex-row items-center justify-center gap-2',
            children: [
              const WIcon(_saveIcon, className: 'size-4'),
              WText(
                variances.isEmpty
                    ? Lang.get('screens.stock_take.finish')
                    : Lang.get('screens.stock_take.save_variances', {'count': variances.length}),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Send every counted row and act on what came back.
  Future<void> _commit(List<CountLine> countedLines) async {
    final ProductController? controller = _controller;

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

    final CountCommit commit = await controller.commitCount(_activeLocation, counts);

    if (!mounted) return;

    setState(() {
      _saving = false;
      _unfinished
        ..clear()
        ..addEntries(commit.unfinished.map((r) => MapEntry(r.productId, r)));

      // Every row that landed is now blind again (D58) against the balance it just corrected.
      // Leaving the typed figure would put a stale number beside a freshly reloaded expected and
      // report a variance that no longer exists.
      for (final CountResult result in commit.lines) {
        if (!result.isUnfinished) {
          _whole.remove(result.productId);
          _inner.remove(result.productId);
        }
      }
    });

    if (commit.error != null) {
      MagicFeedback.error(Lang.get('screens.stock_take.title'), commit.error!);

      return;
    }

    if (commit.unfinished.isEmpty) {
      MagicFeedback.success(
        Lang.get('screens.stock_take.title'),
        Lang.get('screens.stock_take.committed', {'count': commit.writtenCount}),
      );
      MagicRoute.to('/');

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
