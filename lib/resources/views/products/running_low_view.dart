import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart' show MSPageScaffold, MSEmptyState;

import '../../../app/controllers/running_low_controller.dart';
import '../../../app/support/plural.dart';
import '../../../app/support/unit_label.dart';
import '../../../ui/components/product_row/product_row.dart';
import '../../../ui/components/section_card/section_card.dart';
import 'product_fixtures.dart';
import 'stock_in_sheet.dart';

/// What is short: the second of `forecasting.md`'s three surfaces.
///
/// ### Why this is not the shopping list
///
/// The two show almost the same rows and answer different questions. This is the
/// DIAGNOSIS: what is short, how sure the app is, and why. The shopping list is the ACTION:
/// what to buy, tick off, and reconcile against a receipt. So the numbers live here and a
/// sentence lives there (D46 turns the tier into the shape of that sentence), and the rows
/// here are not tickable, dismissable or reorderable, because a diagnosis is not a document
/// the user edits.
///
/// The containment runs one way and a test locks it in: every product here is on the
/// shopping list, and the shopping list also carries expiring and manual rows, so it is a
/// superset. `test/running_low_test.dart` asserts both directions of that, because this app
/// has already shipped a list and a detail page disagreeing about one product.
///
/// ### The tier IS the structure (D57)
///
/// `forecasting.md` gates hard on history: below roughly ten movements, no forecast at all.
/// Rather than hiding that behind a uniform list, the tier is the group heading, and each
/// group says in one line what it is allowed to claim. A user who wants to know why the app
/// is confident about the bulgur and vague about the milk can read it off the screen instead
/// of taking the ranking on faith.
///
/// Days of cover appears only in the top group, because that is the only tier where it
/// exists. It is not omitted from the others as an editorial choice; there is no number.
///
/// ### Out of stock is its own group, not the worst kind of low
///
/// Zero is not a degree of short: there is nothing left to ration and no question of how
/// soon to act. It leads, it does not fold, and it is ordered above the tiers so a
/// well-forecast product with four days of cover never outranks something already gone.
@immutable
class RunningLowView extends StatefulWidget {
  /// Rows supplied by the caller, which is how the preview catalog stays offline.
  ///
  /// Null means "read [RunningLowController]", which is what the route does. The preview passes the
  /// fixture, and the state class only touches the controller when this is null, so previewing this
  /// screen never issues a request.
  final List<ProductListItem>? rows;

  /// Creates the [RunningLowView], reading from [RunningLowController].
  const RunningLowView({super.key, this.rows});

  /// Creates the view with nothing short.
  const RunningLowView.empty({super.key}) : rows = const <ProductListItem>[];

  @override
  State<RunningLowView> createState() => _RunningLowViewState();
}

class _RunningLowViewState extends State<RunningLowView> {
  static const IconData _emptyIcon = Icons.inventory_outlined;

  /// The controller, or null when the caller supplied its own rows.
  RunningLowController? _controller;

  @override
  void initState() {
    super.initState();

    if (widget.rows != null) return;

    final RunningLowController controller = RunningLowController.instance
      ..addListener(_onControllerChanged);

    // `Magic.findOrPut` registers the instance and nothing calls `onInit` for a plain
    // `StatefulWidget`, so without this the screen reports that nothing is short, which is the one
    // wrong answer it can give.
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

  /// Everything short, whatever the source.
  ///
  /// **Not filtered here.** The server decided membership, because the predicate needs the whole
  /// tenant's projection, the consumption rate and how often this tenant shops. A second predicate
  /// in Dart is exactly the drift D57's containment test exists to catch.
  List<ProductListItem> get _all => widget.rows ?? _controller?.rows ?? const <ProductListItem>[];

  /// Whether there is an answer, as opposed to no answer YET.
  ///
  /// Nothing short is the good outcome, like an empty shopping list, so it has to read as one, and
  /// it cannot be shown while the request is still in flight.
  bool get _hasAnswer => widget.rows != null || (_controller?.loaded ?? false);

  /// Gone entirely: its own group, above the tiers.
  List<ProductListItem> get _outOfStock =>
      _all.where((ProductListItem p) => p.isOut).toList(growable: false);

  /// Short but not empty, in the tier that says how much to trust the ranking.
  List<ProductListItem> _lowInTier(ForecastTier tier) =>
      _all.where((ProductListItem p) => !p.isOut && p.tier == tier).toList(growable: false);

  /// What each tier is allowed to say, in the user's own terms.
  static String _tierNote(ForecastTier tier) => switch (tier) {
    ForecastTier.forecast => Lang.get('screens.running_low.note_forecast'),
    ForecastTier.rough => Lang.get('screens.running_low.note_rough'),
    ForecastTier.target => Lang.get('screens.running_low.note_target'),
  };

  static String _tierLabel(ForecastTier tier) => switch (tier) {
    ForecastTier.forecast => Lang.get('screens.running_low.tier_forecast'),
    ForecastTier.rough => Lang.get('screens.running_low.tier_rough'),
    ForecastTier.target => Lang.get('screens.running_low.tier_target'),
  };

  @override
  Widget build(BuildContext context) {
    final List<ProductListItem> out = _hasAnswer ? _outOfStock : const [];
    final bool anything = _hasAnswer && _all.isNotEmpty;

    return MSPageScaffold(
      title: Lang.get('screens.running_low.title'),
      subtitle: anything
          ? Lang.get('screens.running_low.subtitle', {
              'short': _all.length,
              'out': out.length,
            })
          : Lang.get('screens.running_low.subtitle_empty'),
      children: [
        if (out.isNotEmpty) _buildOut(context, out),
        for (final ForecastTier tier in ForecastTier.values)
          if (_hasAnswer && _lowInTier(tier).isNotEmpty) _buildTier(context, tier),
        if (_hasAnswer && !anything) _buildEmpty(),
      ],
    );
  }

  /// Gone entirely. Leads, and does not fold.
  Widget _buildOut(BuildContext context, List<ProductListItem> rows) {
    return SectionCard(
      label: Lang.get('screens.running_low.out_group'),
      count: plural('screens.running_low.product_count', rows.length, {'count': rows.length}),
      children: [for (final ProductListItem p in rows) _buildRow(context, p)],
    );
  }

  /// One certainty tier, with a line saying what it may claim.
  Widget _buildTier(BuildContext context, ForecastTier tier) {
    final List<ProductListItem> rows = _lowInTier(tier);

    return SectionCard(
      label: _tierLabel(tier),
      count: plural('screens.running_low.product_count', rows.length, {'count': rows.length}),
      collapsible: true,
      children: [
        // The honesty made legible. Without it the three groups are three unexplained
        // headings and the user has to guess whether the order means anything.
        WText(_tierNote(tier), className: 'text-xs text-fg-muted'),
        for (final ProductListItem p in rows) _buildRow(context, p),
      ],
    );
  }

  /// One row, rendered by the same `ProductRow` the stock list uses.
  ///
  /// **The on-hand figure is NOT restated in the meta line.** A first pass wrote
  /// `'0,80 / 2 kg'` there and got two numbers wrong at once: `formatted` is the WHOLE
  /// count, so a product holding 2.5 read as "2 / 4" and one holding 0.67 read as "0 / 2"
  /// inside a group that is not the out-of-stock group. The row already renders the amount
  /// correctly through `primaryFigure` plus `remainderFigure` (D26: a count and an open
  /// remainder, never one decimal), so the meta carries only what the row does not: the
  /// target, and the cover figure where one exists.
  ///
  /// Cover is suppressed when the product is out. "0 günlük kaldı" beside a group heading
  /// that already says "Stok bitti" is a true statement adding nothing.
  ///
  /// **The cover leads and the target follows, and that order was measured.** `ProductRow`'s
  /// meta slot truncates, so at 390px the row read `Target 20 pieces · 9 day…`: the one
  /// figure this screen exists to produce was the one that fell off the end, and the target
  /// it kept is on screen twice over anyway (the group heading names the tier and the detail
  /// screen carries the number). Whichever half has to go, it is the context and not the
  /// deadline.
  ///
  /// Tapping goes to stock-in rather than to the product page, because the answer to "this
  /// is short" is almost always "I bought some".
  Widget _buildRow(BuildContext context, ProductListItem product) {
    final (String primary, String? primaryUnit) = product.primaryFigure;
    final (String, String?)? remainder = product.remainderFigure;
    final bool showsCover = product.daysOfCover != null && !product.isOut;
    final num? par = product.parLevel;

    return ProductRow(
      name: product.name,
      meta: [
        if (showsCover)
          plural('screens.running_low.meta_cover', product.daysOfCover!, {
            'days': product.daysOfCover,
          }),
        // **A row can reach this screen with no target at all**, which it could not when the
        // membership test was `parLevel != null && amount < parLevel`. Running out needs no
        // threshold to be true, so an empty product appears whether or not anyone ever said how
        // much of it to keep, and the meta says which of the two it is rather than rendering
        // `Target null`.
        if (par == null)
          Lang.get('screens.running_low.meta_no_target')
        else
          Lang.get('screens.running_low.meta_target', {
            'par': par,
            'unit': unitLabel(product.unit, par),
          }),
      ].join(' · '),
      amount: product.amount,
      formatted: primary,
      unit: primaryUnit,
      remainderFormatted: remainder?.$1,
      remainderUnit: remainder?.$2,
      // **No `parLevel`, so no stock badge**, and that is the one caller of `ProductRow` that
      // wants none. The badge says "running low" on a screen titled "Running low", inside a
      // group heading that already says which KIND of low it is, and it costs the trailing
      // column the width the cover figure needs. An expiry badge still renders: `_buildBadge`
      // ranks expiry above stock level, and a short product that is also going off is worth
      // saying, because that one has a deadline reordering cannot fix.
      onTap: () => StockInSheet.show(context, product: product),
    );
  }

  /// Nothing short, which is the good outcome.
  Widget _buildEmpty() {
    return SectionCard(
      label: Lang.get('screens.running_low.title'),
      children: [
        WDiv(
          // Full width so MSEmptyState's own `items-center` has something to centre in.
          className: 'w-full',
          child: MSEmptyState(
            icon: _emptyIcon,
            title: Lang.get('screens.running_low.empty_title'),
            // Names the mechanism, and names the gap: a product with no target can never
            // appear here however low it gets, which is worth saying to someone looking at
            // an empty screen with a half-empty pantry.
            description: Lang.get('screens.running_low.empty_description'),
          ),
        ),
      ],
    );
  }
}
