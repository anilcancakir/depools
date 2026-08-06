import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart'
    show MSBottomSheet, MSButton, MSSegmentedControl, ButtonIntent;

import '../../../ui/components/quantity/quantity.dart';
import 'product_fixtures.dart';

/// Why stock is leaving.
///
/// The list is short and closed on purpose. `data-model.md` makes the reason
/// load-bearing: forecasting sums consumption and excludes waste, and the waste
/// metric is a filter on this field. A free-text reason would make both
/// uncomputable, and a longer list would make the most frequent action slower.
enum StockOutReason {
  /// Used, eaten, fitted, sold. The default, and the only one forecasting counts.
  consumed,

  /// Spoiled, broken, discarded. Deliberately separate from consumption: a product
  /// thrown away is not demand, and counting it as demand would have the app
  /// recommend buying more of what the user keeps wasting.
  wasted,

  /// A count correction. Not demand and not waste, just the ledger catching up with
  /// reality, so it is excluded from both metrics.
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

  /// Creates a [StockOutSheet].
  const StockOutSheet({super.key, required this.product});

  /// Opens the sheet and resolves with the recorded movement, or null if dismissed.
  static Future<StockOutDraft?> show(BuildContext context, {required ProductListItem product}) {
    return MSBottomSheet.show<StockOutDraft>(
      context,
      title: 'Stok çıkar',
      description: product.name,
      body: StockOutSheet(product: product),
    );
  }

  @override
  State<StockOutSheet> createState() => _StockOutSheetState();
}

/// What the sheet returns: enough to write one movement row.
@immutable
class StockOutDraft {
  /// Which lot the stock came out of.
  final LotFixture lot;

  /// How much, in the unit the user chose.
  final num amount;

  /// The unit the user entered, base or content.
  final String unit;

  /// Why it left.
  final StockOutReason reason;

  /// Whether this take opens a sealed lot.
  final bool opensLot;

  /// Creates a [StockOutDraft].
  const StockOutDraft({
    required this.lot,
    required this.amount,
    required this.unit,
    required this.reason,
    this.opensLot = false,
  });
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

  late LotFixture _lot = _fefoLot;
  StockOutReason _reason = StockOutReason.consumed;

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

  /// The lot FEFO would take from: the open one, else the earliest expiring.
  LotFixture get _fefoLot {
    final List<LotFixture> live = widget.product.liveLots;
    final LotFixture? open = live.where((l) => l.isOpen).firstOrNull;
    if (open != null) return open;

    return live.reduce(
      (a, b) => (a.daysUntilExpiry ?? 9999) <= (b.daysUntilExpiry ?? 9999) ? a : b,
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
    final num? content = widget.product.contentAmount;
    final String? contentUnit = widget.product.contentUnit;
    final String base = widget.product.unit;

    if (_lot.isOpen) {
      // The open lot's remainder is already expressed in the content unit, so its
      // formatted figure is the amount.
      final num remaining = _lot.remaining * (content ?? 1);
      return <_AmountOption>[
        if (remaining > 1)
          _AmountOption(
            amount: remaining / 2,
            unit: contentUnit ?? base,
            label: '${(remaining / 2).round()} ${contentUnit ?? base}',
          ),
        _AmountOption(
          amount: remaining,
          unit: contentUnit ?? base,
          label: '${remaining.round()} ${contentUnit ?? base} · hepsi',
          emptiesLot: true,
        ),
      ];
    }

    return <_AmountOption>[
      _AmountOption(amount: 1, unit: base, label: '1 $base', emptiesLot: _lot.remaining == 1),
      if (content != null && contentUnit != null)
        _AmountOption(
          amount: content / 2,
          unit: contentUnit,
          label: '${(content / 2).round()} $contentUnit',
          opensLot: true,
        ),
    ];
  }

  /// What the product will hold after this take, as a sentence the user can check.
  String get _resultLabel {
    final _AmountOption? option = _amount;
    if (option == null) return 'Çıkarılacak bir şey yok';

    final num content = widget.product.contentAmount ?? 1;
    final num inBase = option.unit == widget.product.unit ? option.amount : option.amount / content;
    final num left = (widget.product.amount - inBase).clamp(0, double.infinity);

    if (left == 0) return 'Sonra: stok kalmayacak';

    final int whole = left.floor();
    final num remainder = ((left - whole) * content).round();

    if (remainder == 0) return 'Sonra: $whole ${widget.product.unit}';
    if (whole == 0) return 'Sonra: $remainder ${widget.product.contentUnit}';
    return 'Sonra: $whole ${widget.product.unit} + $remainder ${widget.product.contentUnit}';
  }

  /// The already-localised label for a reason.
  static String _reasonLabel(StockOutReason reason) => switch (reason) {
    StockOutReason.consumed => 'Tüketildi',
    StockOutReason.wasted => 'Zayi',
    StockOutReason.correction => 'Düzeltme',
  };

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
          'Neden',
          MSSegmentedControl<StockOutReason>(
            options: _reasons.map(_reasonLabel).toList(),
            selectedIndex: _reasons.indexOf(_reason),
            onChanged: (i) => setState(() => _reason = _reasons[i]),
          ),
        ),

        if (widget.product.liveLots.length > 1)
          _group(
            'Hangi parti',
            WDiv(
              className: 'flex flex-col gap-1',
              children: [for (final LotFixture lot in widget.product.liveLots) _lotOption(lot)],
            ),
          ),

        _group(
          'Ne kadar',
          WDiv(
            className: 'flex flex-row wrap gap-2',
            children: [for (final _AmountOption option in options) _amountButton(option)],
          ),
        ),

        WDiv(
          className: 'flex flex-col gap-2 pt-2',
          children: [
            // The outcome, before committing. Same principle as the filter sheet's
            // count: a user about to empty their last carton should see that first,
            // and with the amount preselected this line is always populated.
            WText(_resultLabel, className: 'text-sm text-fg-muted'),
            MSButton(
              onPressed: _amount == null
                  ? null
                  : () => Navigator.of(context).pop(
                      StockOutDraft(
                        lot: _lot,
                        amount: _amount!.amount,
                        unit: _amount!.unit,
                        reason: _reason,
                        opensLot: _amount!.opensLot,
                      ),
                    ),
              // MSButton takes `disabled` separately and does not infer it from a
              // null callback, so passing only the null left this looking like a
              // live primary button while nothing was selected.
              disabled: _amount == null,
              fullWidth: true,
              className: 'justify-center',
              child: const WText('Çıkar'),
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
    final bool selected = lot == _lot;
    final bool suggested = lot == _fefoLot;

    return WAnchor(
      onTap: () => setState(() {
        _lot = lot;
        // The offered amounts depend on the lot, so a stale selection would let the
        // user take 500 ml out of a lot that has none. Re-preselect rather than clear,
        // so changing the lot never leaves the sheet in a state its button rejects.
        _amount = _options.firstOrNull;
      }),
      semanticLabel: '${lot.expiryLabel ?? ''} partisini seç',
      child: WDiv(
        className: '''
          flex flex-row items-center gap-3 px-3 min-h-11 rounded-md
          selected:bg-primary-container selected:border selected:border-color-border
        ''',
        states: selected ? const {'selected'} : const {},
        children: [
          WDiv(
            className: 'flex flex-col gap-0.5 flex-1 min-w-0',
            children: [
              WText(
                [if (lot.isOpen) 'Açık', ?lot.expiryLabel].join(' · '),
                className: 'text-sm text-fg truncate',
              ),
              if (suggested) WText('önerilen · en yakın tarih', className: 'text-xs text-expiring'),
            ],
          ),
          Quantity(amount: lot.remaining, formatted: lot.formatted, unit: lot.unit),
        ],
      ),
    );
  }

  /// One amount button, naming its side effect when it has one.
  Widget _amountButton(_AmountOption option) {
    final bool selected = option.label == _amount?.label;

    return MSButton(
      onPressed: () => setState(() => _amount = option),
      intent: selected ? ButtonIntent.primary : ButtonIntent.secondary,
      className: 'min-h-11 axis-min',
      child: WDiv(
        className: 'flex flex-col items-start gap-0 axis-min',
        children: [
          WText(option.label),
          // Naming the side effect on the button is the point. Opening a carton
          // shortens its expiry from the printed date to a few days, and a user who
          // discovers that afterwards has been told the opposite of the truth.
          if (option.opensLot) WText('kartonu açar', className: 'text-xs opacity-70'),
        ],
      ),
    );
  }
}
