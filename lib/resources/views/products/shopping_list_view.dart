import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart'
    show MSPageScaffold, MSButton, ButtonIntent, MSEmptyState;

import '../../../ui/components/section_card/section_card.dart';
import '../../../ui/components/shopping_row/shopping_row.dart';
import 'shopping_fixtures.dart';

/// The shopping list: what to buy, why, and what is already in the trolley.
///
/// **The reason column is the feature.** `forecasting.md`'s third acceptance criterion is
/// that every line states why it is there, and its own argument is that a checkable
/// suggestion is one the user can trust. A list of names and numbers is a list you either
/// believe or ignore; a list that says "2 günlük kaldı" next to the milk is one you can
/// argue with, and arguing with it is how it earns its place.
///
/// ### The uncertainty answer (D46)
///
/// The doc left this open, noting that no precedent was found for showing a probabilistic
/// inventory forecast to a non-technical user. The answer here is that the PRECISION OF THE
/// SENTENCE is the display: a number where there is a forecast, a bucket where there is
/// only an average, a bare ratio where there is neither. Nothing new to learn, nothing that
/// can be misread as measurement, and it fails safe.
///
/// ### Ticking is not stock (D47)
///
/// A tick means the thing is in the trolley. Stock arrives when the receipt is scanned or a
/// stock-in is recorded. A tick that wrote a movement would give every user phantom
/// inventory for everything they picked up and put back, and it would double-count the
/// moment the receipt landed. So the ticked group is titled with where the items are, and
/// the action under it is the one that actually closes the loop.
///
/// ### Ticked lines sink
///
/// Into their own group, so the list of what is left keeps shrinking as the trip goes on.
/// That is what every list app converged on and the reason is the same here: progress you
/// can see, and a shorter list to re-scan at the next aisle.
@immutable
class ShoppingListView extends StatelessWidget {
  static const IconData _addIcon = Icons.add;
  static const IconData _receiptIcon = Icons.receipt_long_outlined;
  static const IconData _emptyIcon = Icons.shopping_basket_outlined;

  /// Whether there is anything on the list.
  ///
  /// The empty list is not a failure state and must not read as one: it means nothing is
  /// running out, which is the outcome the whole forecasting feature exists to produce.
  final bool hasLines;

  /// Creates the [ShoppingListView] mid-trip.
  const ShoppingListView({super.key}) : hasLines = true;

  /// Creates the view with nothing to buy.
  const ShoppingListView.empty({super.key}) : hasLines = false;

  @override
  Widget build(BuildContext context) {
    return MSPageScaffold(
      title: 'Alışveriş listesi',
      subtitle: hasLines
          ? '${pendingLines.length} ürün alınacak · ${checkedLines.length} sepette'
          : 'Eksik yok',
      children: hasLines
          ? [_buildPending(), if (checkedLines.isNotEmpty) _buildChecked(), _buildActions()]
          : [_buildEmpty(), _buildActions()],
    );
  }

  /// What is left to get, urgency first.
  Widget _buildPending() {
    return SectionCard(
      label: 'Alınacak',
      count: '${pendingLines.length} ürün',
      children: [
        for (final ShoppingFixture line in pendingLines)
          ShoppingRow(
            name: line.name,
            amount: line.amount,
            formatted: line.formatted,
            unit: line.unit,
            reason: line.reason,
            reasonDetail: line.reasonDetail,
            onToggle: () {},
          ),
      ],
    );
  }

  /// What is in the trolley. Collapsible, because it only grows.
  Widget _buildChecked() {
    return SectionCard(
      label: 'Sepette',
      count: '${checkedLines.length} ürün',
      collapsible: true,
      children: [
        for (final ShoppingFixture line in checkedLines)
          ShoppingRow(
            name: line.name,
            amount: line.amount,
            formatted: line.formatted,
            unit: line.unit,
            reason: line.reason,
            reasonDetail: line.reasonDetail,
            isChecked: true,
            onToggle: () {},
          ),
      ],
    );
  }

  /// Nothing to buy, which is the good outcome and has to read like one.
  Widget _buildEmpty() {
    return SectionCard(
      label: 'Alınacak',
      children: [
        WDiv(
          // Full width so MSEmptyState's own `items-center` has something to centre in.
          className: 'w-full',
          child: MSEmptyState(
            icon: _emptyIcon,
            title: 'Şu an eksik yok',
            // Says the mechanism rather than apologising for the blank: a product appears
            // here once it has a target level or enough history to run one.
            description:
                'Hedef seviyesi belirlenmiş ve azalan ürünler burada görünür. '
                'Yeterli geçmiş biriktikçe tahmin de devreye girer.',
          ),
        ),
      ],
    );
  }

  /// Add a line, and close the loop once there is something to close it with.
  Widget _buildActions() {
    return WDiv(
      className: 'flex flex-col gap-2 pb-2',
      children: [
        MSButton(
          onPressed: () {},
          intent: ButtonIntent.ghost,
          fullWidth: true,
          className: 'justify-center',
          child: const WDiv(
            className: 'flex flex-row items-center justify-center gap-2',
            children: [
              WIcon(_addIcon, className: 'size-4'),
              WText('Ürün ekle'),
            ],
          ),
        ),
        // Appears only once something is in the trolley, because that is when it means
        // anything. Absent rather than disabled: a disabled primary button is visually
        // indistinguishable from a live one in this theme, measured.
        if (hasLines && checkedLines.isNotEmpty) ...[
          WText('Sepettekiler stoğa fiş tarandığında girer', className: 'text-xs text-fg-muted'),
          MSButton(
            onPressed: () {},
            fullWidth: true,
            className: 'justify-center',
            child: const WDiv(
              className: 'flex flex-row items-center justify-center gap-2',
              children: [
                WIcon(_receiptIcon, className: 'size-4'),
                WText('Fişi tara'),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
