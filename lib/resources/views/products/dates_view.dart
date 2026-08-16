import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart' show MSPageScaffold, MSEmptyState;

import '../../../app/controllers/expiring_controller.dart';
import '../../../ui/components/choice_chip/choice_chip.dart';
import '../../../ui/components/lot_row/lot_row.dart';
import '../../../ui/components/section_card/section_card.dart';
import 'expiring_fixtures.dart';
import 'product_fixtures.dart';
import 'stock_out_sheet.dart';

/// What is running out of time: the first of `forecasting.md`'s three surfaces and the one
/// it calls the most immediately valuable, because it needs no forecast at all.
///
/// ### The scope is a horizon the user sets (D55)
///
/// An earlier draft of this screen filtered on each product's own D24 window, reasoning that
/// one number cannot serve a five-day milk and a one-year flour. Measured, it produced ZERO
/// rows: D24's window for a five-day product is one day, so a carton with two days left was
/// excluded from the one screen built to find it.
///
/// The two thresholds do different jobs. D24 decides what earns a badge UNPROMPTED, on a
/// screen the user did not open to ask about dates. This screen IS that question, so its
/// scope is an absolute horizon with chips, and urgency inside it is carried by
/// `ExpiryBadge`, which has a tuned threshold of its own.
///
/// ### Every row is a lot, including the ones that are not (D56)
///
/// A product with a lot breakdown contributes one row per lot, because a carton expiring
/// Tuesday and one expiring next month are two decisions; showing the product would say
/// something needs using without saying which one to reach for. A product carrying a single
/// date contributes one row: its implicit lot. One row type, no exceptions.
///
/// ### Expired leads, and its action is different
///
/// A date that has passed is a decision rather than a warning: the stock gets used anyway or
/// written off, and it will not improve. So it sits in its own group at the top, and tapping
/// a row there opens the stock-out sheet with `waste` ALREADY CHOSEN. Making the user
/// restate what they just tapped on is the kind of friction that ends with nobody recording
/// waste, and waste is the number this product sells.
///
/// ### Not a food screen
///
/// A warranty ending in two days sits next to a cheese that went off yesterday, and the
/// label says which is which. Filtering warranties out would be one more place the food
/// assumption got baked in.
@immutable
class DatesView extends StatefulWidget {
  /// Whether there is anything dated at all.
  ///
  /// An empty list is the good outcome here, exactly as it is on the shopping list, and it
  /// has to read like one.
  final bool hasRows;

  /// Rows supplied by the caller, which is how the preview catalog stays offline.
  ///
  /// Null means "read [ExpiringController]", which is what the route does. The preview passes the
  /// fixture, and the state class only touches the controller when this is null, so previewing this
  /// screen never issues a request.
  final List<DatedLot>? rows;

  /// Creates the [DatesView], reading from [ExpiringController].
  const DatesView({super.key, this.rows}) : hasRows = true;

  /// Creates the view with nothing approaching.
  const DatesView.empty({super.key}) : rows = const <DatedLot>[], hasRows = false;

  @override
  State<DatesView> createState() => _DatesViewState();
}

class _DatesViewState extends State<DatesView> {
  static const IconData _emptyIcon = Icons.event_available_outlined;
  static const List<int> _horizons = <int>[3, 7, 30];

  int _horizon = defaultHorizonDays;

  /// The controller, or null when the caller supplied its own rows.
  ExpiringController? _controller;

  @override
  void initState() {
    super.initState();

    if (widget.rows != null) return;

    final ExpiringController controller = ExpiringController.instance
      ..addListener(_onControllerChanged);

    // Same `onInit` contract every wired screen here needs: `Magic.findOrPut` registers the
    // instance and nothing calls `onInit` for a plain `StatefulWidget`, so without this the screen
    // would report that nothing is going off, which is the one wrong answer this screen can give.
    if (!controller.initialized) controller.onInit();

    _controller = controller;
    _horizon = controller.horizon;
  }

  @override
  void dispose() {
    _controller?.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  /// Everything inside the current horizon, whatever the source.
  List<DatedLot> get _all => widget.rows ?? _controller?.rows ?? const <DatedLot>[];

  /// Whether there is anything to show, as opposed to nothing YET.
  ///
  /// An empty list is the good outcome here, so it cannot be shown until it is an answer: "nothing
  /// is running out" while the request is in flight is the one wrong thing this screen can say.
  bool get _hasAnswer => widget.rows != null || (_controller?.loaded ?? false);

  /// Rows already past their date, which lead and do not fold.
  List<DatedLot> get _expired =>
      _all.where((DatedLot row) => row.isExpired).toList();

  /// Rows still good, grouped by where they are, in the order the payload lists them.
  ///
  /// **Grouped by the location's own NAME from the row**, rather than by walking a separate
  /// location list. `forecasting.md` asks for the grouping because a cafe's morning check is a walk
  /// to the fridge, then the freezer, then the dry store, and the walk is what the order has to
  /// match. The rows arrive sorted by date, so a location appears where its most urgent row does.
  Map<String, List<DatedLot>> get _approaching {
    final Map<String, List<DatedLot>> grouped = <String, List<DatedLot>>{};

    for (final DatedLot row in _all) {
      if (row.isExpired) continue;

      grouped.putIfAbsent(row.locationName ?? row.locationId, () => <DatedLot>[]).add(row);
    }

    return grouped;
  }

  /// Ask for a different horizon, which is a REQUEST rather than a filter over what is held.
  void _setHorizon(int days) {
    setState(() => _horizon = days);

    _controller?.load(horizon: days);
  }

  @override
  Widget build(BuildContext context) {
    final List<DatedLot> expired = _hasAnswer ? _expired : const <DatedLot>[];
    final Map<String, List<DatedLot>> groups = _hasAnswer
        ? _approaching
        : const <String, List<DatedLot>>{};
    final int approaching = groups.values.fold(0, (sum, rows) => sum + rows.length);

    return MSPageScaffold(
      title: Lang.get('screens.dates.title'),
      subtitle: _hasAnswer && (expired.isNotEmpty || groups.isNotEmpty)
          ? Lang.get('screens.dates.subtitle', {
              'days': _horizon,
              'approaching': approaching,
              'expired': expired.length,
            })
          : Lang.get('screens.dates.subtitle_empty'),
      children: [
        if (_hasAnswer) _buildHorizon(),
        if (expired.isNotEmpty) _buildExpired(expired),
        for (final MapEntry<String, List<DatedLot>> group in groups.entries)
          _buildLocation(group.key, group.value),
        if (_hasAnswer && expired.isEmpty && groups.isEmpty) _buildEmpty(),
      ],
    );
  }

  /// How far ahead to look.
  ///
  /// Chips rather than a date picker: the question is "this week or this month", not "before
  /// the 14th", and three answers cover it. The expired group is outside the horizon by
  /// definition, so narrowing to three days never hides something already off.
  Widget _buildHorizon() {
    return SectionCard(
      label: Lang.get('screens.dates.horizon_label'),
      children: [
        WDiv(
          className: 'flex flex-row wrap items-center gap-2 py-1',
          children: [
            for (final int days in _horizons)
              ChoiceChip(
                label: Lang.get('screens.dates.horizon_chip', {'days': days}),
                isSuggested: days == _horizon,
                // The selected chip has to SAY it is selected. Its tint is the only other
                // signal and a screen reader cannot see a tint, so without this the current
                // horizon is unknowable: three chips announcing "show N days" with no
                // indication of which one is already showing.
                semanticLabel: days == _horizon
                    ? Lang.get('screens.dates.horizon_selected', {'days': days})
                    : Lang.get('screens.dates.horizon_apply', {'days': days}),
                onTap: () => _setHorizon(days),
              ),
          ],
        ),
      ],
    );
  }

  /// Already past their date. Leads, and does not fold.
  ///
  /// Every other group here could reasonably be collapsed once checked; this one is work
  /// rather than evidence, and a group whose whole purpose is to demand a decision cannot
  /// offer to hide itself. Same call the receipt review's unresolved group makes.
  Widget _buildExpired(List<DatedLot> rows) {
    return SectionCard(
      label: Lang.get('screens.dates.expired_group'),
      count: Lang.get('screens.dates.lot_count', {'count': rows.length}),
      children: [for (final DatedLot row in rows) _buildRow(row, isExpired: true)],
    );
  }

  /// One location's approaching rows, soonest first.
  Widget _buildLocation(String path, List<DatedLot> rows) {
    return SectionCard(
      label: path,
      count: '${rows.length} parti',
      collapsible: true,
      children: [for (final DatedLot row in rows) _buildRow(row)],
    );
  }

  /// One row, rendered by the same `LotRow` a product's own page uses.
  Widget _buildRow(DatedLot row, {bool isExpired = false}) {
    return WAnchor(
      onTap: () => _openStockOut(row, isExpired: isExpired),
      semanticLabel: isExpired
          ? Lang.get('screens.dates.row_waste', {
              'product': row.productName,
              'label': row.label,
            })
          : Lang.get('screens.dates.row_stock_out', {
              'product': row.productName,
              'label': row.label,
            }),
      child: LotRow(
        productName: row.productName,
        remainingAmount: row.remaining,
        remaining: row.formatted,
        unit: row.unit,
        expiryLabel: row.label,
        daysUntilExpiry: row.daysUntilExpiry,
        receivedLabel: row.receivedLabel,
        lotCode: row.lotCode,
        isOpen: row.isOpen,
        openedLabel: row.receivedLabel,
      ),
    );
  }

  /// Straight into the stock-out sheet, with the reason already decided when it is obvious.
  void _openStockOut(DatedLot row, {required bool isExpired}) {
    final ProductListItem product = productFixtures.firstWhere(
      (p) => p.name == row.productName,
      orElse: () => productFixtures.first,
    );

    StockOutSheet.show(context, product: product, reason: isExpired ? StockOutReason.waste : null);
  }

  /// Nothing approaching, which is the good outcome.
  Widget _buildEmpty() {
    return SectionCard(
      label: Lang.get('screens.dates.title'),
      children: [
        WDiv(
          // Full width so MSEmptyState's own `items-center` has something to centre in.
          className: 'w-full',
          child: MSEmptyState(
            icon: _emptyIcon,
            title: Lang.get('screens.dates.empty_title'),
            // Names the mechanism rather than apologising for the blank, and says which
            // dates count, since a warranty appears here too.
            description: Lang.get('screens.dates.empty_description'),
          ),
        ),
      ],
    );
  }
}
