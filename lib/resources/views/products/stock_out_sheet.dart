import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart'
    show MSBottomSheet, MSButton, MSSegmentedControl, ButtonIntent;

import '../../../app/support/unit_label.dart';
import '../../../ui/components/option_row/option_row.dart';
import '../../../ui/components/quantity/quantity.dart';
import 'product_fixtures.dart';

/// Why stock is leaving.
///
/// **These names are `data-model.md`'s `stock_movements.reason` values, not the UI's
/// own vocabulary.** An earlier version invented `consumed` and `wasted`, which would
/// have needed a translation layer at the API boundary and given two names to one
/// concept. The schema's list is load-bearing: forecasting sums `consumption` and
/// excludes `waste`, and the waste metric is a ratio of this field.
///
/// The schema has eight values; these are the four a user picks from THIS sheet.
/// `purchase` comes from stock-in, `transfer_out` from the move flow, `return` from a
/// supplier flow. Each surface offers only the reasons it can legitimately produce.
enum StockOutReason {
  /// Used, eaten, fitted, sold. The default, and the only one forecasting counts.
  consumption,

  /// Spoiled, broken, discarded. Deliberately separate from consumption: a product
  /// thrown away is not demand, and counting it as demand would have the app
  /// recommend buying more of what the user keeps wasting.
  waste,

  /// A counted correction after a physical count. The ledger catching up with reality.
  stockTake,

  /// Fixing a data-entry error. Split from [stockTake] because the schema splits them:
  /// both are excluded from demand, but one says the shelf was wrong and the other
  /// says the record was, and only the second suggests the app made entry too easy to
  /// get wrong.
  correction,
}

/// Take stock out of a product: the most frequent action in the app.
///
/// Everything here is shaped by that frequency. It opens with a lot already chosen,
/// offers the two or three amounts a user actually enters as one-tap buttons, and
/// shows what will be left before anything is committed. A form that needed four
/// deliberate choices would be correct and unused.
///
/// ### The lot is preselected by FEFO
///
/// First-expiring, first-out. The open lot wins when there is one, because it is
/// already on a shorter clock than anything sealed. That is not only waste
/// prevention: it is what the user is physically holding, since the opened carton is
/// the one at the front of the fridge.
///
/// The choice is still visible and changeable. An automatic default that cannot be
/// overridden is how a user ends up fighting the app when they took the carton from
/// the back.
///
/// ### Consuming part of a sealed unit opens it, without asking
///
/// Taking 500 ml from a sealed 1 lt carton produces an open lot with 500 ml left and
/// starts its after-opening clock (D27). The user never says "I am opening this";
/// they say what they used, and the state follows. This is D13 and D29 applied: act
/// on the fact, do not interrogate.
///
/// The button that will do it says so ("kartonu açar"), because a silent state change
/// that shortens an expiry date is exactly the kind of thing a user needs to see
/// coming.
class StockOutSheet extends StatefulWidget {
  /// The product stock is leaving.
  final ProductListItem product;

  /// The reason to start on, when the caller already knows it.
  final StockOutReason? initialReason;

  /// Creates a [StockOutSheet].
  const StockOutSheet({super.key, required this.product, this.initialReason});

  /// Opens the sheet, optionally with the reason already chosen.
  ///
  /// The dates screen passes `waste` when the row it came from is already past its date:
  /// arriving at this sheet from an expired lot and having to pick "Zayi" again is asking
  /// the user to restate what they just tapped on.
  static Future<StockOutDraft?> show(
    BuildContext context, {
    required ProductListItem product,
    StockOutReason? reason,
  }) {
    return MSBottomSheet.show<StockOutDraft>(
      context,
      title: Lang.get('screens.stock_out.title'),
      description: product.name,
      body: StockOutSheet(product: product, initialReason: reason),
    );
  }

  @override
  State<StockOutSheet> createState() => _StockOutSheetState();
}

/// What the sheet returns: enough to write one movement row.
///
/// Either a lot and an amount, or a single serial. Never both, because the two unit
/// models are exclusive per product (D28) and a draft that could carry both would
/// invite a caller to guess which one it meant.
@immutable
class StockOutDraft {
  /// Which lot the stock came out of, for a lot-tracked product.
  final LotFixture? lot;

  /// Which specific unit left, for a serial-tracked product.
  final SerialFixture? serial;

  /// How much, in the unit the user chose. Always 1 for a serial.
  final num amount;

  /// The unit the user entered, base or content.
  final String unit;

  /// Why it left.
  final StockOutReason reason;

  /// Whether this take opens a sealed lot.
  final bool opensLot;

  /// Creates a [StockOutDraft].
  const StockOutDraft({
    required this.amount,
    required this.unit,
    required this.reason,
    this.lot,
    this.serial,
    this.opensLot = false,
  }) : assert((lot == null) != (serial == null), 'StockOutDraft: exactly one of lot or serial.');
}

/// One offered amount, and what taking it means.
@immutable
class _AmountOption {
  final num amount;
  final String unit;
  final String label;
  final bool opensLot;
  final bool emptiesLot;

  const _AmountOption({
    required this.amount,
    required this.unit,
    required this.label,
    this.opensLot = false,
    this.emptiesLot = false,
  });
}

class _StockOutSheetState extends State<StockOutSheet> {
  static const List<StockOutReason> _reasons = StockOutReason.values;

  /// The lot in play, for a lot-tracked product. Null in serial mode.
  late LotFixture? _lot = _fefoLot;

  /// The unit in play, for a serial-tracked product. Null in lot mode.
  late SerialFixture? _serial = _soonestWarranty;
  late StockOutReason _reason = widget.initialReason ?? StockOutReason.consumption;

  /// The chosen amount, preselected rather than left empty.
  ///
  /// **Nothing here starts unanswered.** FEFO picks the lot and this picks the most
  /// likely amount, so the most frequent action in the app is two taps: open the
  /// sheet, confirm. A sheet that demanded a choice before its button did anything
  /// was one tap longer on every single stock-out.
  ///
  /// It also removed the need for a disabled primary button, which is just as well:
  /// `MSButton`'s `disabled` produced no visible change at all in this intent, so the
  /// button looked live while doing nothing. That is a `magic_starter` issue rather
  /// than one to paper over here, but designing the state away is better than
  /// depending on it.
  late _AmountOption? _amount = _options.firstOrNull;

  /// Whether this product is tracked unit by unit.
  bool get _isSerial => widget.product.tracking == TrackingMode.serial;

  /// The lot FEFO would take from: the open one, else the earliest expiring.
  ///
  /// Null for a serial-tracked product, which has no lots. An earlier version reduced
  /// the empty list and threw `Bad state: No element` the moment anyone tapped "Stok
  /// çıkar" on a serial product. That is the THIRD lot-shaped assumption D28 has
  /// broken, and this one I shipped.
  LotFixture? get _fefoLot {
    final List<LotFixture> live = widget.product.liveLots;
    if (live.isEmpty) return null;

    final LotFixture? open = live.where((l) => l.isOpen).firstOrNull;
    if (open != null) return open;

    return live.reduce(
      (a, b) => (a.daysUntilExpiry ?? 9999) <= (b.daysUntilExpiry ?? 9999) ? a : b,
    );
  }

  /// The unit to offer first: the one whose warranty runs down soonest.
  ///
  /// The same intuition as FEFO, for the same reason. A unit loses value as its
  /// warranty burns, so a shop is better off moving that one first. It is a suggestion
  /// rather than a rule, since a serial is a specific object and the user may be
  /// holding a different one.
  SerialFixture? get _soonestWarranty {
    final List<SerialFixture> live = widget.product.liveSerials;
    if (live.isEmpty) return null;

    return live.reduce(
      (a, b) => (a.warrantyDaysRemaining ?? 9999) <= (b.warrantyDaysRemaining ?? 9999) ? a : b,
    );
  }

  /// The amounts worth a one-tap button for the selected lot.
  ///
  /// **The offers differ by whether the lot is already open**, which is the whole
  /// point. An open 500 ml lot offers half and all of what remains. A sealed 1 lt
  /// carton offers the whole unit, and a half that will open it.
  ///
  /// Nothing is offered when the product declares no content, because there is no
  /// smaller unit to express: a bag of nails goes out in whole nails.
  List<_AmountOption> get _options {
    // A serial-tracked take is one specific object, so there is no amount to choose.
    // Offering "1 adet" as a button would be a control with one option.
    if (_isSerial || _lot == null) return const <_AmountOption>[];

    final num? content = widget.product.contentAmount;
    final String? contentUnit = widget.product.contentUnit;
    final String base = widget.product.unit;

    if (_lot!.isOpen) {
      // The open lot's remainder is already expressed in the content unit, so its
      // formatted figure is the amount.
      final num remaining = _lot!.remaining * (content ?? 1);
      return <_AmountOption>[
        if (remaining > 1)
          _AmountOption(
            amount: remaining / 2,
            unit: contentUnit ?? base,
            label: Lang.get('screens.stock_out.quick_half', {'amount': (remaining / 2).round(), 'unit': contentUnit ?? base}),
          ),
        _AmountOption(
          amount: remaining,
          unit: contentUnit ?? base,
          label: Lang.get('screens.stock_out.quick_all', {'amount': remaining.round(), 'unit': contentUnit ?? base}),
          emptiesLot: true,
        ),
      ];
    }

    return <_AmountOption>[
      _AmountOption(amount: 1, unit: base, label: '1 $base', emptiesLot: _lot!.remaining == 1),
      if (content != null && contentUnit != null)
        _AmountOption(
          amount: content / 2,
          unit: contentUnit,
          label: Lang.get('screens.stock_out.quick_half', {
            'amount': (content / 2).round(),
            'unit': unitLabel(contentUnit, (content / 2).round()),
          }),
          opensLot: true,
        ),
    ];
  }

  /// Whether there is a complete answer to commit.
  bool get _canCommit => _isSerial ? _serial != null : _amount != null;

  /// What the product will hold after this take, as a sentence the user can check.
  String get _resultLabel {
    if (_isSerial) {
      final int left = widget.product.liveSerials.length - (_serial == null ? 0 : 1);
      return left == 0 ? Lang.get('screens.stock_out.left_none') : Lang.get('screens.stock_out.left_simple', {'amount': left, 'unit': unitLabel(widget.product.unit, left)});
    }

    final _AmountOption? option = _amount;
    if (option == null) return Lang.get('screens.stock_out.nothing_to_take');

    final num content = widget.product.contentAmount ?? 1;
    final num inBase = option.unit == widget.product.unit ? option.amount : option.amount / content;
    final num left = (widget.product.amount - inBase).clamp(0, double.infinity);

    if (left == 0) return Lang.get('screens.stock_out.left_none');

    final int whole = left.floor();
    final num remainder = ((left - whole) * content).round();

    if (remainder == 0) return Lang.get('screens.stock_out.left_simple', {'amount': whole, 'unit': unitLabel(widget.product.unit, whole)});
    if (whole == 0) return Lang.get('screens.stock_out.left_simple', {'amount': remainder, 'unit': unitLabel(widget.product.contentUnit ?? '', remainder)});
    return Lang.get('screens.stock_out.left_split', {'whole': whole, 'unit': unitLabel(widget.product.unit, whole), 'remainder': remainder, 'contentUnit': unitLabel(widget.product.contentUnit ?? '', remainder)});
  }

  /// The already-localised label for a reason, which varies by tracking mode.
  ///
  /// **The enum does not vary, only the wording.** `consumed` means "left as demand"
  /// either way, and forecasting depends on that staying one value. But "Tüketildi" on
  /// a power drill is wrong in Turkish and in English, and a shop reading it would
  /// reasonably pick "Düzeltme" instead, which would corrupt the very metric the
  /// distinction exists to protect.
  String _reasonLabel(StockOutReason reason) {
    final bool serial = widget.product.tracking == TrackingMode.serial;
    return switch (reason) {
      StockOutReason.consumption => serial ? Lang.get('screens.stock_out.reason_sold') : Lang.get('screens.stock_out.reason_consumed'),
      StockOutReason.waste => Lang.get('screens.stock_out.reason_waste'),
      StockOutReason.stockTake => Lang.get('screens.stock_out.reason_count'),
      StockOutReason.correction => Lang.get('screens.stock_out.reason_correction'),
    };
  }

  @override
  Widget build(BuildContext context) {
    final List<_AmountOption> options = _options;

    return WDiv(
      className: 'flex flex-col gap-5',
      children: [
        // Reason first, not last. It changes what the numbers MEAN (waste is not
        // demand, and forecasting excludes it), and a user recording spoilage knows
        // that before they know how much. Asking last also invites leaving it on the
        // default, which would quietly log every thrown-out carton as consumption.
        _group(
          Lang.get('screens.stock_out.reason_group'),
          MSSegmentedControl<StockOutReason>(
            options: _reasons.map(_reasonLabel).toList(),
            selectedIndex: _reasons.indexOf(_reason),
            onChanged: (i) => setState(() => _reason = _reasons[i]),
          ),
        ),

        if (_isSerial)
          _group(
            Lang.get('screens.stock_out.unit_group'),
            WDiv(
              className: 'flex flex-col gap-1',
              children: [
                for (final SerialFixture unit in widget.product.liveSerials) _serialOption(unit),
              ],
            ),
          )
        else ...[
          if (widget.product.liveLots.length > 1)
            _group(
              Lang.get('screens.stock_out.lot_group'),
              WDiv(
                className: 'flex flex-col gap-1',
                children: [for (final LotFixture lot in widget.product.liveLots) _lotOption(lot)],
              ),
            ),

          // No amount section in serial mode. A unit is whole, so a control with one
          // option would be a question with one answer.
          _group(
            Lang.get('screens.stock_out.amount_group'),
            WDiv(
              className: 'flex flex-row wrap gap-2',
              children: [for (final _AmountOption option in options) _amountButton(option)],
            ),
          ),
        ],

        WDiv(
          className: 'flex flex-col gap-2 pt-2',
          children: [
            // The outcome, before committing. Same principle as the filter sheet's
            // count: a user about to empty their last carton should see that first,
            // and with the amount preselected this line is always populated.
            WText(_resultLabel, className: 'text-sm text-fg-muted'),
            MSButton(
              onPressed: _canCommit
                  ? () => Navigator.of(context).pop(
                      _isSerial
                          ? StockOutDraft(
                              serial: _serial,
                              amount: 1,
                              unit: widget.product.unit,
                              reason: _reason,
                            )
                          : StockOutDraft(
                              lot: _lot,
                              amount: _amount!.amount,
                              unit: _amount!.unit,
                              reason: _reason,
                              opensLot: _amount!.opensLot,
                            ),
                    )
                  : null,
              // MSButton takes `disabled` separately and does not infer it from a
              // null callback, so passing only the null left this looking like a
              // live primary button while nothing was selected.
              disabled: !_canCommit,
              fullWidth: true,
              className: 'justify-center',
              child: WText(Lang.get('screens.stock_out.submit')),
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

  /// One selectable lot, showing what FEFO thinks and why.
  Widget _lotOption(LotFixture lot) {
    return OptionRow(
      label: [if (lot.isOpen) Lang.get('screens.stock_out.open'), ?lot.expiryLabel].join(' · '),
      suggestionReason: lot == _fefoLot ? Lang.get('screens.stock_out.suggested_soonest') : null,
      isSelected: lot == _lot,
      semanticLabel: Lang.get('screens.stock_out.pick_lot', {'label': lot.expiryLabel ?? ''}),
      onTap: () => setState(() {
        _lot = lot;
        // The offered amounts depend on the lot, so a stale selection would let the
        // user take 500 ml out of a lot that has none. Re-preselect rather than clear,
        // so changing the lot never leaves the sheet in a state its button rejects.
        _amount = _options.firstOrNull;
      }),
      trailing: Quantity(amount: lot.remaining, formatted: lot.formatted, unit: lot.unit),
    );
  }

  /// One selectable unit, for a serial-tracked product.
  ///
  /// The serial leads in mono, because that is the unit's identity and the thing the
  /// user is matching against the object in their hand. The warranty follows, since it
  /// is what makes one unit a better one to move than another.
  Widget _serialOption(SerialFixture unit) {
    return OptionRow(
      label: unit.serial,
      isMono: true,
      suggestionReason: unit == _soonestWarranty ? Lang.get('screens.stock_out.suggested_warranty') : null,
      isSelected: unit == _serial,
      semanticLabel: Lang.get('screens.stock_out.pick_unit', {'serial': unit.serial}),
      onTap: () => setState(() => _serial = unit),
      trailing: unit.warrantyLabel == null
          ? null
          : WText(unit.warrantyLabel!, className: 'text-xs text-fg-muted'),
    );
  }

  /// One amount button, naming its side effect when it has one.
  Widget _amountButton(_AmountOption option) {
    final bool selected = option.label == _amount?.label;

    return MSButton(
      onPressed: () => setState(() => _amount = option),
      intent: selected ? ButtonIntent.primary : ButtonIntent.secondary,
      className: 'py-3 axis-min',
      child: WDiv(
        className: 'flex flex-col items-start gap-0 axis-min',
        children: [
          WText(option.label),
          // Naming the side effect on the button is the point. Opening a carton
          // shortens its expiry from the printed date to a few days, and a user who
          // discovers that afterwards has been told the opposite of the truth.
          if (option.opensLot) WText(Lang.get('screens.stock_out.opens_pack'), className: 'text-xs opacity-70'),
        ],
      ),
    );
  }
}
