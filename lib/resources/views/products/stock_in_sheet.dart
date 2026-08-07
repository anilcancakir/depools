import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart' show MSBottomSheet, MSButton, ButtonIntent;

import '../../../ui/components/option_row/option_row.dart';
import 'product_filter_sheet.dart' show FilterOption;
import 'product_fixtures.dart';

/// Put stock into a product.
///
/// The counterpart to [StockOutSheet] and the same shape for the same reason: this is
/// done many times a day, so every field arrives with an answer already in it and the
/// user's job is to disagree rather than to fill.
///
/// **Three things are inferred here, and each states where it came from.**
///
/// - The amount includes a "top up to target" offer, computed from the product's par
///   level against what is on hand. That is the number a user restocking actually
///   wants and the one they would otherwise work out in their head at the shelf.
/// - The location is suggested by placement history, and the suggestion SHOWS ITS
///   REASON ("3 kez buraya konuldu"). `location-assignment.md` builds the affinity
///   model; this is where its output has to earn trust. A suggestion with no visible
///   basis is a guess the user learns to ignore.
/// - The expiry date is pre-filled from the shelf life, and says so. `D29` forbids
///   asking for what can be inferred, but an inferred DATE that does not admit it is
///   how a wrong one becomes load-bearing for a forecast.
///
/// Everything inferred is changeable in one tap. That is the difference between
/// inference and assumption.
class StockInSheet extends StatefulWidget {
  /// The product stock is arriving for.
  final ProductListItem product;

  /// Creates a [StockInSheet].
  const StockInSheet({super.key, required this.product});

  /// Opens the sheet and resolves with the draft movement, or null if dismissed.
  static Future<StockInDraft?> show(BuildContext context, {required ProductListItem product}) {
    return MSBottomSheet.show<StockInDraft>(
      context,
      title: 'Stok ekle',
      description: product.name,
      body: StockInSheet(product: product),
    );
  }

  @override
  State<StockInSheet> createState() => _StockInSheetState();
}

/// What the sheet returns: enough to write one inbound movement and open a lot.
@immutable
class StockInDraft {
  /// How many base units arrived.
  final num amount;

  /// Where they went.
  final String locationId;

  /// The already-formatted expiry the user accepted or picked, when the product
  /// tracks one.
  final String? expiryLabel;

  /// Creates a [StockInDraft].
  const StockInDraft({required this.amount, required this.locationId, this.expiryLabel});
}

class _StockInSheetState extends State<StockInSheet> {
  late num _amount = _amountOptions.first.$1;
  late String _locationId = _suggestedLocationId;

  /// The amounts worth a one-tap button.
  ///
  /// One and two are the everyday cases. The third is the gap to the target level,
  /// offered only when there IS a target and the product is under it, because
  /// "hedefe tamamla" on something already stocked is noise.
  List<(num, String)> get _amountOptions {
    final num? par = widget.product.parLevel;
    final num gap = par == null ? 0 : (par - widget.product.amount).ceil();

    return <(num, String)>[
      (1, '1 ${widget.product.unit}'),
      (2, '2 ${widget.product.unit}'),
      if (gap > 2) (gap, '$gap · hedefe tamamla'),
    ];
  }

  /// Where placement history says this goes.
  ///
  /// Standing in for the affinity model: the location already holding the most of
  /// this product. That is the same signal the real model ranks first
  /// (`location-assignment.md` puts co-location affinity above name semantics), so
  /// the UI is being designed against the right shape of answer.
  String get _suggestedLocationId {
    // Goes through `amountAt`, which is mode-aware. Counting lots suggested
    // "Buzdolabı" for a power drill whose two units sit on a warehouse shelf, because
    // a serial-tracked product has no lots and the fallback took the first option. The
    // fourth lot-shaped assumption D28 has broken.
    final List<String> ids = locationOptions
        .map((o) => o.id)
        .where((id) => widget.product.amountAt(id) > 0)
        .toList();

    if (ids.isEmpty) return locationOptions.first.id;

    return ids.reduce((a, b) => widget.product.amountAt(a) >= widget.product.amountAt(b) ? a : b);
  }

  /// Why that location was suggested, in the user's words.
  ///
  /// Says "parti" or "ünite" depending on the unit model, because "burada 2 parti var"
  /// on a serial-tracked drill is a word the screen uses nowhere else.
  String _suggestionReason(String locationId) {
    // The COUNT is the explanation. `location-assignment.md` makes that explicit: the
    // affinity number is not internal state, it is what the user is shown so the
    // suggestion is arguable rather than magic.
    final (String, int)? byCategory = suggestLocationFor(widget.product.categoryId);
    if (byCategory != null && byCategory.$1 == locationId) {
      return 'önerilen · buraya ${byCategory.$2} kez konuldu';
    }

    final num here = widget.product.amountAt(locationId);
    if (here == 0) return 'Önerilen';

    final String noun = widget.product.tracking == TrackingMode.serial ? 'ünite' : 'parti';
    return 'önerilen · burada ${here.floor()} $noun var';
  }

  /// The locations to offer, suggestion first.
  ///
  /// Blind `take(3)` hid the drill's own shelf, which is fifth in the list, so the one
  /// place its stock actually lives was not offered at all. The suggestion always
  /// appears, and the rest fill the remaining slots.
  List<FilterOption> get _offeredLocations {
    final FilterOption suggested = locationOptions.firstWhere((o) => o.id == _suggestedLocationId);
    final List<FilterOption> rest = locationOptions
        .where((o) => o.id != suggested.id)
        .take(2)
        .toList();

    return <FilterOption>[suggested, ...rest];
  }

  /// The expiry the shelf life implies, and the sentence explaining it.
  ///
  /// Null when the product declares no shelf life, in which case the sheet does not
  /// ask for a date at all. Inventing a date field for a box of screws is how a form
  /// gets long enough to be abandoned.
  (String, String)? get _suggestedExpiry {
    final int? life = widget.product.shelfLifeDays;
    if (life == null) return null;

    final DateTime now = DateTime.now();
    final DateTime date = now.add(Duration(days: life));
    const List<String> months = [
      'Oca',
      'Şub',
      'Mar',
      'Nis',
      'May',
      'Haz',
      'Tem',
      'Ağu',
      'Eyl',
      'Eki',
      'Kas',
      'Ara',
    ];

    // The YEAR appears whenever it is not this one. A two-year warranty rendered
    // "5 Ağu" and read as this week, which is the opposite of what it meant. Omitting
    // it inside the current year keeps the common perishable case short.
    final String day = '${date.day} ${months[date.month - 1]}';
    final String label = date.year == now.year ? day : '$day ${date.year}';

    return (label, '$_dateBasis ($life gün)');
  }

  /// What the date on this product means, which is not the same for both unit models.
  ///
  /// A carton has a printed expiry; a drill has a warranty end. Labelling both "Son
  /// kullanma" put a food word on a power tool, which is the D2 framing mistake in
  /// miniature: expiry is one kind of date this app holds, not the only kind.
  String get _dateGroupLabel =>
      widget.product.tracking == TrackingMode.serial ? 'Garanti bitişi' : 'Son kullanma';

  /// Where the suggested date came from, phrased for what it is.
  String get _dateBasis =>
      widget.product.tracking == TrackingMode.serial ? 'garanti süresinden' : 'raf ömründen';

  /// What the product will hold after this arrival.
  String get _resultLabel {
    final num content = widget.product.contentAmount ?? 1;
    final num total = widget.product.amount + _amount;
    final int whole = total.floor();
    final num remainder = ((total - whole) * content).round();

    if (remainder == 0) return 'Kalan: $whole ${widget.product.unit}';
    return 'Kalan: $whole ${widget.product.unit} + $remainder ${widget.product.contentUnit}';
  }

  @override
  Widget build(BuildContext context) {
    final (String, String)? expiry = _suggestedExpiry;

    return WDiv(
      className: 'flex flex-col gap-5',
      children: [
        _group(
          'Ne kadar',
          WDiv(
            className: 'flex flex-row wrap gap-2',
            children: [
              for (final (num value, String label) in _amountOptions)
                MSButton(
                  onPressed: () => setState(() => _amount = value),
                  intent: _amount == value ? ButtonIntent.primary : ButtonIntent.secondary,
                  className: 'py-3 axis-min',
                  child: WText(label),
                ),
            ],
          ),
        ),

        _group(
          'Nereye',
          WDiv(
            className: 'flex flex-col gap-1',
            children: [
              for (final FilterOption option in _offeredLocations) _locationOption(option),
            ],
          ),
        ),

        if (expiry != null)
          _group(
            _dateGroupLabel,
            WDiv(
              className: 'flex flex-row items-center gap-2',
              children: [
                MSButton(
                  onPressed: () {},
                  intent: ButtonIntent.secondary,
                  className: 'py-3 axis-min',
                  child: WText(expiry.$1),
                ),
                // The basis, not just the value. An inferred date that does not admit
                // it is how a wrong one silently becomes the input to a forecast.
                WText(expiry.$2, className: 'text-xs text-fg-muted'),
              ],
            ),
          ),

        WDiv(
          className: 'flex flex-col gap-2 pt-2',
          children: [
            WText(_resultLabel, className: 'text-sm text-fg-muted'),
            MSButton(
              onPressed: () => Navigator.of(context).pop(
                StockInDraft(amount: _amount, locationId: _locationId, expiryLabel: expiry?.$1),
              ),
              fullWidth: true,
              className: 'justify-center',
              child: const WText('Ekle'),
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

  Widget _locationOption(FilterOption option) {
    final bool suggested = option.id == _suggestedLocationId;

    return OptionRow(
      label: option.fullPath,
      suggestionReason: suggested ? _suggestionReason(option.id) : null,
      isSelected: option.id == _locationId,
      semanticLabel: '${option.fullPath} konumunu seç',
      onTap: () => setState(() => _locationId = option.id),
    );
  }
}
