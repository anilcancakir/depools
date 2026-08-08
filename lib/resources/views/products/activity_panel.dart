import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart'
    show MSBottomSheet, MSButton, ButtonIntent, ButtonSize;

import '../../../ui/components/movement_row/movement_row.dart';
import '../../../ui/components/section_card/section_card.dart';
import 'activity_fixtures.dart';

/// Everything the app has written, and the way back out of it.
///
/// **A panel, not a screen** (D50). It opens from the header in both shells, because the
/// entries already live where they belong: in the assistant transcript in one mode, on the
/// product's own movement list in the other. This is the cross-cutting view of what
/// happened while the user was not looking, which full automation makes necessary, and a
/// third screen would be a third place the same rows live.
///
/// ### Undo is a movement, not a delete
///
/// D51. The ledger is append-only, so reversing a write appends a compensating
/// `correction` that references the original. Both rows stay visible: the correction on
/// top, the original struck through beneath it. Collapsing the pair would be tidier and
/// would hide half the arithmetic, and `forecasting.md` asks for balances that reconcile
/// against the visible history by hand.
///
/// The consequence worth stating plainly: **undo does not make anything disappear.** It
/// makes a second thing happen, and the feed shows both.
///
/// ### An undo that cannot work says so before it is tapped
///
/// D52. Validity is a question about ledger state, not about a clock: undo is offered
/// exactly when the compensating movement would keep the invariants, and there is no time
/// window. When it would not, the row carries the blocking fact instead of a control.
/// A greyed button with no reason is a dead end, and in this theme a disabled `MSButton`
/// is visually indistinguishable from a live one anyway.
@immutable
class ActivityPanel extends StatelessWidget {
  /// Creates the [ActivityPanel] body.
  const ActivityPanel({super.key});

  /// Opens the panel over whichever shell the user is in.
  static Future<void> show(BuildContext context) {
    return MSBottomSheet.show<void>(
      context,
      title: Lang.get('screens.activity.title'),
      description: automaticWrites == 0
          ? Lang.get('screens.activity.subtitle')
          : Lang.get('screens.activity.subtitle_auto', {'count': automaticWrites}),
      body: const ActivityPanel(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WDiv(
      className: 'flex flex-col gap-4',
      children: [for (final ActivityDay day in activityDays) _buildDay(day)],
    );
  }

  /// One day, newest first.
  Widget _buildDay(ActivityDay day) {
    return SectionCard(
      label: day.label,
      count: '${day.entries.length} hareket',
      children: [for (final ActivityFixture entry in day.entries) _buildEntry(entry)],
    );
  }

  /// One entry, rendered by the same `MovementRow` the product's own history uses.
  ///
  /// That is the point of putting undo on the row rather than on this panel: three
  /// surfaces show movements, and three renderings of one fact are three chances to
  /// disagree about it.
  Widget _buildEntry(ActivityFixture entry) {
    return MovementRow(
      // The product leads here; see ActivityFixture for why the two surfaces differ.
      reason: entry.product,
      deltaAmount: entry.deltaAmount,
      delta: entry.delta,
      unit: entry.unit,
      meta: entry.meta,
      direction: entry.direction,
      isReversed: entry.undo == UndoState.reversed,
      note: entry.note,
      action: entry.undo == UndoState.available
          ? MSButton(
              onPressed: () {},
              intent: ButtonIntent.ghost,
              size: ButtonSize.sm,
              semanticLabel: Lang.get('screens.activity.undo_label', {'product': entry.product, 'reason': entry.reason}),
              child: WText(Lang.get('screens.activity.undo')),
            )
          : null,
    );
  }
}
