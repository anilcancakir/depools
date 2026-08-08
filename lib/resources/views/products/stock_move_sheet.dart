import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart' show MSBottomSheet, MSButton, ButtonIntent;

import '../../../ui/components/option_row/option_row.dart';
import '../../../ui/components/quantity/quantity.dart';
import 'product_fixtures.dart';

/// Move stock from one location to another.
///
/// **A move is one user action and two ledger rows.** `data-model.md` invariant 5: a
/// transfer writes exactly two movements with equal and opposite deltas and a shared
/// reference, `transfer_out` and `transfer_in`. Nothing here lets the two drift apart,
/// which is why the sheet commits a single draft rather than two independent entries.
///
/// ### Both endpoints are constrained, and that is the whole difficulty
///
/// The source can only be a location that HOLDS some of this product, and the destination
/// can only be a location that is not the source. A picker that offered every location on
/// both sides would let a user construct a move of nothing from nowhere, and the error
/// would surface at commit rather than at the tap.
///
/// So the destination list is derived AFTER the source is chosen, and changing the source
/// re-derives it. That is also why the destination suggestion is not simply the affinity
/// winner: the affinity model's best answer is often where the stock already is, which is
/// exactly the one place it cannot go.
class StockMoveSheet extends StatefulWidget {
  /// The product being moved.
  final ProductListItem product;

  /// Creates a [StockMoveSheet].
  const StockMoveSheet({super.key, required this.product});

  /// Opens the sheet and resolves with the paired move, or null if dismissed.
  static Future<StockMoveDraft?> show(BuildContext context, {required ProductListItem product}) {
    return MSBottomSheet.show<StockMoveDraft>(
      context,
      title: Lang.get('screens.stock_move.title'),
      description: product.name,
      body: StockMoveSheet(product: product),
    );
  }

  @override
  State<StockMoveSheet> createState() => _StockMoveSheetState();
}

/// What the sheet returns: enough to write the movement PAIR.
///
/// One object rather than two, because the two rows are not independently valid: an outbound
/// without its inbound is stock that vanished.
@immutable
class StockMoveDraft {
  /// Where it left.
  final String fromLocationId;

  /// Where it arrived.
  final String toLocationId;

  /// How much, in the unit the user chose.
  final num amount;

  /// The unit the user entered.
  final String unit;

  /// Creates a [StockMoveDraft].
  const StockMoveDraft({
    required this.fromLocationId,
    required this.toLocationId,
    required this.amount,
    required this.unit,
  }) : assert(fromLocationId != toLocationId, 'StockMoveDraft: a move needs two places.');
}

class _StockMoveSheetState extends State<StockMoveSheet> {
  late String? _from = _sources.firstOrNull;
  String? _to;

  /// The chosen amount, preselected like the source and the destination.
  ///
  /// **Nothing here starts unanswered**, which is the same call the stock-out sheet made
  /// and for a harder reason: `MSButton`'s `disabled` produces no visible change in the
  /// primary intent (measured), so a sheet that opens with an incomplete draft shows a
  /// button that looks live and refuses. Preselecting removes the state instead of
  /// depending on a disabled look that does not exist.
  late num? _amount = _options.firstOrNull?.$1;
  late String? _amountUnit = _options.firstOrNull?.$2;

  /// Locations that actually hold some of this product.
  List<String> get _sources =>
      locationOptions.map((o) => o.id).where((id) => widget.product.amountAt(id) > 0).toList();

  /// Locations this stock could go to: anywhere but where it already is.
  List<String> get _destinations =>
      locationOptions.map((o) => o.id).where((id) => id != _from).toList();

  /// Where to propose sending it.
  ///
  /// Category affinity, EXCEPT when affinity points at the source. The affinity model's
  /// best answer is usually where the stock already sits, which is the one place a move
  /// cannot end, so falling through to the next option is not a fallback here: it is the
  /// normal case.
  String? get _suggestedDestination {
    final (String, int)? byCategory = suggestLocationFor(widget.product.categoryId);
    if (byCategory != null && byCategory.$1 != _from) return byCategory.$1;
    return _destinations.firstOrNull;
  }

  /// The amounts worth a one-tap button, given what the source holds.
  ///
  /// A move offers whole units and, when something is open there, that remainder. Moving an
  /// opened carton is a real thing (the fridge to the shop floor), and it carries its
  /// after-opening clock with it rather than resetting.
  List<(num, String, String)> get _options => _from == null ? const [] : _optionsFor(_from!);

  /// The amounts a specific source can offer, so a source change can re-derive them before
  /// `_from` has been committed to state.
  List<(num, String, String)> _optionsFor(String locationId) {
    final num here = widget.product.amountAt(locationId);
    final int whole = here.floor();
    final String base = widget.product.unit;
    final String? contentUnit = widget.product.contentUnit;
    final num? content = widget.product.contentAmount;
    final num remainder = ((here - whole) * (content ?? 1)).round();

    return <(num, String, String)>[
      if (whole >= 1) (1, base, '1 $base'),
      if (whole > 1) (whole, base, '$whole $base · hepsi'),
      if (remainder > 0 && contentUnit != null)
        (remainder, contentUnit, Lang.get('screens.stock_move.quick_open', {'amount': remainder, 'unit': contentUnit})),
    ];
  }

  /// Whether there is a complete, valid move to commit.
  bool get _canCommit => _from != null && _to != null && _amount != null && _from != _to;

  /// What each end will hold afterwards, which is the check a user actually wants.
  String get _resultLabel {
    if (!_canCommit) return Lang.get('screens.stock_move.nothing');

    final String fromName = resolveLocationLabel(_from!) ?? _from!;
    final String toName = resolveLocationLabel(_to!) ?? _to!;
    return Lang.get('screens.stock_move.after_note', {'from': fromName, 'to': toName});
  }

  @override
  Widget build(BuildContext context) {
    final List<(num, String, String)> options = _options;
    _to ??= _suggestedDestination;

    return WDiv(
      className: 'flex flex-col gap-5',
      children: [
        _group(
          Lang.get('screens.stock_move.from_group'),
          WDiv(
            className: 'flex flex-col gap-1',
            children: [for (final String id in _sources) _sourceOption(id)],
          ),
        ),
        _group(
          Lang.get('screens.stock_move.amount_group'),
          WDiv(
            className: 'flex flex-row wrap gap-2',
            children: [
              for (final (num value, String unit, String label) in options)
                MSButton(
                  onPressed: () => setState(() {
                    _amount = value;
                    _amountUnit = unit;
                  }),
                  intent: _amount == value && _amountUnit == unit
                      ? ButtonIntent.primary
                      : ButtonIntent.secondary,
                  className: 'py-3 axis-min',
                  child: WText(label),
                ),
            ],
          ),
        ),
        _group(
          Lang.get('screens.stock_move.to_group'),
          WDiv(
            className: 'flex flex-col gap-1',
            children: [for (final String id in _destinations.take(4)) _destinationOption(id)],
          ),
        ),
        WDiv(
          className: 'flex flex-col gap-2 pt-2',
          children: [
            WText(_resultLabel, className: 'text-sm text-fg-muted'),
            MSButton(
              onPressed: _canCommit
                  ? () => Navigator.of(context).pop(
                      StockMoveDraft(
                        fromLocationId: _from!,
                        toLocationId: _to!,
                        amount: _amount!,
                        unit: _amountUnit!,
                      ),
                    )
                  : null,
              disabled: !_canCommit,
              fullWidth: true,
              className: 'justify-center',
              child: WText(Lang.get('screens.stock_move.submit')),
            ),
          ],
        ),
      ],
    );
  }

  Widget _group(String label, Widget control) {
    return WDiv(
      className: 'flex flex-col gap-2',
      children: [
        WText(label, className: 'text-xs font-medium uppercase tracking-wide text-fg-muted'),
        control,
      ],
    );
  }

  /// One source, showing what it holds so the choice is informed.
  Widget _sourceOption(String id) {
    final num here = widget.product.amountAt(id);
    final int whole = here.floor();
    final num content = widget.product.contentAmount ?? 1;
    final num remainder = ((here - whole) * content).round();

    return OptionRow(
      label: resolveLocationPath(id) ?? id,
      isSelected: id == _from,
      semanticLabel: Lang.get('screens.stock_move.pick_from', {'path': resolveLocationPath(id)}),
      onTap: () => setState(() {
        _from = id;
        // The destination list and the amounts both derive from the source, so a stale
        // selection would let the user move 500 ml out of a place that has none, or into
        // the place it came from. Re-preselect rather than clear, so changing the source
        // never leaves the sheet in a state its own button refuses.
        _to = null;
        _amount = _optionsFor(id).firstOrNull?.$1;
        _amountUnit = _optionsFor(id).firstOrNull?.$2;
      }),
      trailing: Quantity(
        amount: here,
        formatted: '$whole',
        unit: widget.product.unit,
        remainderFormatted: remainder > 0 ? '$remainder' : null,
        remainderUnit: remainder > 0 ? widget.product.contentUnit : null,
        size: QuantitySize.sm,
      ),
    );
  }

  Widget _destinationOption(String id) {
    final bool suggested = id == _suggestedDestination;
    final (String, int)? affinity = suggestLocationFor(widget.product.categoryId);
    final bool affinityMatches = affinity != null && affinity.$1 == id;

    return OptionRow(
      label: resolveLocationPath(id) ?? id,
      suggestionReason: !suggested
          ? null
          : affinityMatches
          ? Lang.get('screens.stock_move.suggested_count', {'count': affinity.$2})
          : Lang.get('screens.stock_move.suggested'),
      isSelected: id == _to,
      semanticLabel: Lang.get('screens.stock_move.pick_to', {'path': resolveLocationPath(id)}),
      onTap: () => setState(() => _to = id),
    );
  }
}
