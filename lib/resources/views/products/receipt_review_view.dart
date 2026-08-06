import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart' show MSPageScaffold, MSButton, ButtonIntent;

import '../../../ui/components/receipt_line_row/receipt_line_row.dart';
import '../../../ui/components/section_card/section_card.dart';
import 'receipt_fixtures.dart';

/// Reviewing a photographed receipt before it becomes stock.
///
/// **Confirmation is mandatory and the doc says why**: a silently inserted wrong line
/// becomes wrong stock the user may not notice for weeks, and a wrong number destroys
/// trust faster than an honest request to check. Every comparable product does the same.
///
/// ### The grouping is the design
///
/// Unresolved lines lead, settled lines follow, dropped lines last. That ordering is what
/// makes a 22-line receipt reviewable: the four that need a decision are at the top with
/// nothing to scroll past, and the seventeen that do not are still there to check against
/// the paper.
///
/// **Unresolved is deliberately NOT collapsible.** Every other section in this app folds,
/// and this one must not: a group whose whole purpose is to demand action cannot offer to
/// hide itself. The other two fold, because they are evidence rather than work.
///
/// ### The commit button counts lines, not everything
///
/// It says how many lines will be written, which is the settled ones. A user with four
/// unresolved lines can still commit the seventeen and come back, because
/// `receipt-ingestion.md` requires the receipt to stay resumable and per-line state to
/// persist. Blocking the commit until every line resolves would turn one awkward
/// abbreviation into a wall.
@immutable
class ReceiptReviewView extends StatelessWidget {
  static const IconData _retakeIcon = Icons.photo_camera_outlined;

  /// Creates the [ReceiptReviewView].
  const ReceiptReviewView({super.key});

  @override
  Widget build(BuildContext context) {
    final int settled = settledLines.length;
    final int unresolved = unresolvedLines.length;

    return MSPageScaffold(
      title: 'Fiş incelemesi',
      subtitle: 'Migros · 5 Ağu 18:22 · ${receiptLines.length} satır',
      actions: [
        MSButton(
          onPressed: () {},
          intent: ButtonIntent.ghost,
          className: 'min-h-11 min-w-11 justify-center',
          semanticLabel: 'Yeniden çek',
          child: const WIcon(_retakeIcon),
        ),
      ],
      children: [
        if (unresolved > 0) _buildUnresolved(),
        _buildSettled(),
        if (rejectedLines.isNotEmpty) _buildRejected(),
        _buildCommit(settled),
      ],
    );
  }

  /// The lines that need a decision. Leads, and does not fold.
  Widget _buildUnresolved() {
    return SectionCard(
      label: 'Eşleştirilemedi',
      count: '${unresolvedLines.length} satır',
      children: [for (final ReceiptLineFixture line in unresolvedLines) _row(line)],
    );
  }

  /// The lines that will be committed as they stand.
  ///
  /// Collapsible but open by default. Seventeen rows the user does not have to touch are
  /// still seventeen rows they should be able to check, because the whole review is a
  /// comparison against the paper in their hand. Folding is what they do once satisfied.
  Widget _buildSettled() {
    return SectionCard(
      label: 'Hazır',
      count: '${settledLines.length} satır',
      collapsible: true,
      children: [for (final ReceiptLineFixture line in settledLines) _row(line)],
    );
  }

  /// The lines the user dropped, kept visible so the receipt still reconciles.
  Widget _buildRejected() {
    return SectionCard(
      label: 'Atlandı',
      count: '${rejectedLines.length} satır',
      collapsible: true,
      initiallyExpanded: false,
      children: [for (final ReceiptLineFixture line in rejectedLines) _row(line)],
    );
  }

  /// The commit pair, with the count of what will actually be written.
  Widget _buildCommit(int settled) {
    return WDiv(
      className: 'flex flex-col gap-2 pb-2',
      children: [
        // Naming the number is the point. "Kaydet" alone would hide that four lines are
        // being left behind, and the user would find out by missing stock later.
        WText(
          '$settled satır stoğa yazılacak, ${unresolvedLines.length} satır bekliyor',
          className: 'text-sm text-fg-muted',
        ),
        MSButton(
          onPressed: () {},
          fullWidth: true,
          className: 'justify-center',
          child: WText('$settled satırı kaydet'),
        ),
        MSButton(
          onPressed: () {},
          intent: ButtonIntent.ghost,
          fullWidth: true,
          className: 'justify-center',
          child: const WText('Fişi at'),
        ),
      ],
    );
  }

  Widget _row(ReceiptLineFixture line) {
    return ReceiptLineRow(
      extracted: line.extracted,
      productName: line.productName,
      resolution: line.resolution,
      amount: line.amount,
      formatted: line.formatted,
      unit: line.unit,
      price: line.price,
      locationLabel: line.locationLabel,
      onTap: () {},
    );
  }
}
