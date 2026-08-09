import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart' show MSButton, ButtonIntent;

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
@immutable
class StockTakeView extends StatefulWidget {
  /// Creates the [StockTakeView].
  const StockTakeView({super.key});

  @override
  State<StockTakeView> createState() => _StockTakeViewState();
}

class _StockTakeViewState extends State<StockTakeView> {
  static const IconData _saveIcon = Icons.playlist_add_check;

  /// Which location is being counted. A count is always scoped to one place, because that is
  /// how a person does it: you stand in front of one shelf.
  String _locationId = 'loc-fridge';

  /// Counts as typed, keyed by product name. Absent means uncounted, which is why this is a
  /// map with holes rather than a list of zeroes.
  final Map<String, num?> _whole = <String, num?>{};
  final Map<String, num?> _inner = <String, num?>{};

  /// The lines for the chosen location, with any typed counts folded in.
  List<CountLine> get _lines => fridgeCount
      .map(
        (line) => CountLine(
          product: line.product,
          expected: line.expected,
          countedWhole: _whole.containsKey(line.product.name)
              ? _whole[line.product.name]
              : line.countedWhole,
          countedRemainder: _inner.containsKey(line.product.name)
              ? _inner[line.product.name]
              : line.countedRemainder,
        ),
      )
      .toList();

  @override
  Widget build(BuildContext context) {
    final List<CountLine> lines = _lines;
    final int counted = lines.where((l) => l.isCounted).length;
    final List<CountLine> variances = lines.where((l) => l.isCounted && !l.isMatched).toList();

    // The commit is the point of this screen and it used to sit at the END of the count, so a
    // forty-line shelf put `Sayımı kaydet` a full scroll away from the last line the user typed.
    // Pinned, it is where the user's thumb already is when they finish.
    return AppPageScaffold(
      title: Lang.get('screens.stock_take.title'),
      subtitle: Lang.get('screens.stock_take.subtitle', {'location': resolveLocationPath(_locationId), 'counted': counted, 'total': lines.length}),
      footer: _buildCommit(lines, counted, variances),
      children: [_buildLocation(), _buildLines(lines)],
    );
  }

  /// Which shelf. Chips rather than a tree, because a count is scoped to one leaf and the
  /// tree's job (finding a place to put something) is not this screen's job.
  Widget _buildLocation() {
    return SectionCard(
      label: Lang.get('screens.stock_take.where_group'),
      children: [
        WDiv(
          className: 'flex flex-row wrap items-center gap-2 py-1',
          children: [
            for (final FilterOption option in locationOptions)
              ChoiceChip(
                label: option.fullPath,
                isSuggested: option.id == _locationId,
                semanticLabel: option.id == _locationId
                    ? Lang.get('screens.stock_take.current_location', {'path': option.fullPath})
                    : Lang.get('screens.stock_take.pick_location', {'path': option.fullPath}),
                onTap: () => setState(() => _locationId = option.id),
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
            remainderUnit: line.product.contentUnit,
            counted: line.countedWhole?.toString(),
            countedRemainder: line.countedRemainder?.toString(),
            verdict: line.verdict,
            state: !line.isCounted
                ? CountState.uncounted
                : line.isMatched
                ? CountState.matched
                : CountState.variance,
            onChanged: (next) => setState(() => _whole[line.product.name] = num.tryParse(next)),
            onDecrement: () => setState(() {
              final num current = line.countedWhole ?? 0;
              _whole[line.product.name] = current <= 0 ? 0 : current - 1;
            }),
            onIncrement: () =>
                setState(() => _whole[line.product.name] = (line.countedWhole ?? 0) + 1),
            onRemainderChanged: (next) =>
                setState(() => _inner[line.product.name] = num.tryParse(next)),
          ),
      ],
    );
  }

  /// What committing will and will not do.
  Widget _buildCommit(List<CountLine> lines, int counted, List<CountLine> variances) {
    final int skipped = lines.length - counted;

    return WDiv(
      className: 'flex flex-col gap-2 pb-2',
      children: [
        // Both numbers, because the second one is the one a user would not think to ask
        // about: the rows they skipped stay exactly as they were.
        WText(
          skipped == 0
              ? Lang.get('screens.stock_take.summary', {'counted': counted, 'variances': variances.length})
              : Lang.get('screens.stock_take.summary_skipped', {'counted': counted, 'skipped': skipped}),
          className: 'text-sm text-fg-muted',
        ),
        if (variances.isNotEmpty)
          WText(
            Lang.get('screens.stock_take.will_write', {'count': variances.length}),
            className: 'text-xs text-fg-muted',
          ),
        MSButton(
          onPressed: () {},
          fullWidth: true,
          className: 'justify-center',
          child: WDiv(
            className: 'flex flex-row items-center justify-center gap-2',
            children: [
              const WIcon(_saveIcon, className: 'size-4'),
              WText(variances.isEmpty ? Lang.get('screens.stock_take.finish') : Lang.get('screens.stock_take.save_variances', {'count': variances.length})),
            ],
          ),
        ),
        MSButton(
          onPressed: () {},
          intent: ButtonIntent.ghost,
          fullWidth: true,
          className: 'justify-center',
          child: WText(Lang.get('screens.stock_take.continue')),
        ),
      ],
    );
  }
}
