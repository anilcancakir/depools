import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart'
    show ButtonIntent, MSButton, MSEmptyState, MSPageScaffold;

import '../../../app/controllers/receipt_controller.dart';
import '../../../app/models/receipt.dart';
import '../../../app/support/date_label.dart';
import '../../../app/support/money_label.dart';
import '../../../app/support/plural.dart';
import '../../../ui/components/option_row/option_row.dart';
import '../../../ui/components/quantity/quantity.dart';
import '../../../ui/components/receipt_line_row/receipt_line_row.dart';
import '../../../ui/components/section_card/section_card.dart';
import 'product_fixtures.dart';

/// Reviewing a photographed receipt before it becomes stock.
///
/// **Confirmation is mandatory and the doc says why**: a silently inserted wrong line
/// becomes wrong stock the user may not notice for weeks, and a wrong number destroys
/// trust faster than an honest request to check. Every comparable product does the same.
///
/// ### Two modes, because there is one route and several receipts
///
/// With nothing selected the screen is the receipt LIST: which of the tenant's receipts to review.
/// Tapping one opens it. That is local state rather than navigation because `/receipt` is the only
/// path the table registers (`lib/routes/app.dart:146`) and `/receipt/:id` belongs to slice 2, where
/// a receipt finally has something to show. The cost is named rather than hidden: a browser back
/// from the detail leaves the screen instead of returning to the list, so the header carries its own
/// way back.
///
/// **A receipt with no lines is the normal state of this whole slice, not an error.** Nothing
/// extracts anything yet, so every real receipt arrives with zero lines and the screen says the
/// reading has not happened. An empty-looking review screen would read as a receipt that came out
/// blank, which is a failure the user cannot act on and did not cause.
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
class ReceiptReviewView extends StatefulWidget {
  /// The tenant's receipts, supplied by the caller, which is how the preview catalog stays offline.
  ///
  /// Null means "read [ReceiptController]", which is what the route does. The catalog is
  /// unauthenticated and offline, so a preview letting the screen reach the controller would fire a
  /// request and draw an error.
  final List<Receipt>? receipts;

  /// One receipt to review, supplied by the caller. Same reason as [receipts], and it also pins the
  /// screen in detail mode: a preview of the review has no list to go back to.
  final Receipt? receipt;

  /// Creates the [ReceiptReviewView], reading from [ReceiptController].
  const ReceiptReviewView({super.key, this.receipts, this.receipt});

  @override
  State<ReceiptReviewView> createState() => _ReceiptReviewViewState();
}

class _ReceiptReviewViewState extends State<ReceiptReviewView> {
  static const IconData _retakeIcon = Icons.photo_camera_outlined;
  static const IconData _backIcon = Icons.arrow_back;
  static const IconData _emptyIcon = Icons.receipt_long_outlined;
  static const IconData _pendingIcon = Icons.hourglass_empty;

  /// The controller, or null when the caller supplied its own data.
  ReceiptController? _controller;

  /// Which receipt the user opened, or null while the list is showing.
  String? _openId;

  @override
  void initState() {
    super.initState();

    if (widget.receipts != null || widget.receipt != null) return;

    final ReceiptController controller = ReceiptController.instance
      ..addListener(_onControllerChanged);

    // `Magic.findOrPut` registers the instance and nothing calls `onInit` for a plain
    // `StatefulWidget`, so without this the screen reports that the tenant has no receipts, which
    // is the one wrong answer it can give: the user has just photographed one.
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

  /// The receipts to choose from, whatever the source.
  List<Receipt> get _receipts => widget.receipts ?? _controller?.receipts ?? const <Receipt>[];

  /// Whether there is an answer, as opposed to no answer YET.
  ///
  /// "No receipts" is a real state a new tenant is in, so it has to read as one, and it cannot be
  /// shown while the first request is still in flight. `setLoading` clears the held list, so the
  /// count alone cannot tell the two apart.
  bool get _hasAnswer => widget.receipts != null || (_controller?.isSuccess ?? false);

  /// Whether the screen is showing one receipt rather than the list.
  bool get _isDetail => widget.receipt != null || _openId != null;

  /// The receipt on screen, or null while its own request is still in flight.
  Receipt? get _open {
    final Receipt? supplied = widget.receipt;

    if (supplied != null) return supplied;

    final Receipt? detail = _controller?.detail;

    // The controller holds ONE detail, so the id has to agree before it is drawn here: a slower
    // response for a receipt the user has since left would otherwise land on this screen.
    return detail != null && detail.id == _openId ? detail : null;
  }

  @override
  Widget build(BuildContext context) => _isDetail ? _buildDetail() : _buildList();

  /// Which receipt to review, as a picker.
  Widget _buildList() {
    final List<Receipt> receipts = _receipts;
    final String? failure = _hasAnswer ? null : _controller?.rxStatus.message;

    return MSPageScaffold(
      title: Lang.get('screens.receipt.title'),
      // **Not `screens.receipt.subtitle`**, which is `:merchant · :date · :count lines` and belongs
      // to a receipt rather than to the list. And no count at all until there is one to state: a
      // header saying zero while the request is in flight is a claim the screen cannot support yet.
      subtitle: _hasAnswer
          ? plural('screens.receipt.list_subtitle', receipts.length, {'count': receipts.length})
          : null,
      children: [
        if (failure != null) _buildFailure(failure, () => _controller?.load()),
        if (_hasAnswer && receipts.isNotEmpty)
          // Headerless: the page IS this one section, and a `RECEIPTS · 3` header under a page
          // titled `Receipt review · 3 receipts` repeats it.
          SectionCard(children: [for (final Receipt receipt in receipts) _option(receipt)]),
        if (_hasAnswer && receipts.isEmpty) _buildEmpty(),
      ],
    );
  }

  /// One receipt in the list.
  ///
  /// **`OptionRow` rather than a new component**, because a receipt list is a picker: choose which
  /// one to review. `docs/component-registry.md`'s rule is to use what covers the need, and what
  /// this row shows (a label, a plain line under it, a figure on the right) is that component's
  /// whole shape.
  Widget _option(Receipt receipt) {
    final String? supplier = receipt.supplierName;
    final DateTime? created = receipt.createdAt;
    final num? total = receipt.totalAmount;
    final int lines = receipt.linesCount ?? receipt.lines.length;

    // **The date branch is the normal path rather than a fallback.** `supplier_name` and `issued_on`
    // are null on every row this slice can produce, so a label reading the supplier alone would
    // render the whole list blank. The third branch is unreachable through the API, which always
    // sends `created_at`, and names the state rather than inventing a date for a payload that could
    // not be read.
    final String label = supplier ??
        (created == null
            ? Lang.get('screens.receipt.status_pending')
            : Lang.get('screens.receipt.uploaded_at', {'date': dateLabel(created)}));

    return OptionRow(
      label: label,
      // `description`, NOT `suggestionReason`: that slot renders in the `ai` tone and would tell the
      // user the app inferred something about a receipt it has not read a single line off.
      //
      // The state is only named while it IS the state this slice writes. There is no copy for the
      // rest of the `receipts.status` vocabulary, and printing "pending" over a confirmed receipt
      // would be worse than saying nothing about it.
      description: <String>[
        if (receipt.status == 'pending') Lang.get('screens.receipt.status_pending'),
        Lang.get('screens.receipt.line_count', {'count': lines}),
      ].join(' · '),
      // Nothing in this slice fills `total_amount`, so this is absent on every real row today and
      // the column is uniform rather than ragged. Slice 2 is what makes it appear.
      trailing: total == null
          ? null
          : Quantity(
              amount: total,
              formatted: moneyLabel(total, receipt.currency),
              size: QuantitySize.sm,
            ),
      semanticLabel: Lang.get('screens.receipt.option_semantic', {'label': label}),
      onTap: () => _select(receipt),
    );
  }

  /// Opens one receipt.
  ///
  /// The list endpoint sends no lines at all (`ReceiptResource` gates them behind `whenLoaded`), so
  /// the detail is a second request rather than a filter over what is already held.
  void _select(Receipt receipt) {
    setState(() => _openId = receipt.id);

    _controller?.open(receipt.id);
  }

  /// One receipt, line by line.
  Widget _buildDetail() {
    final Receipt? receipt = _open;
    final List<ReceiptLine> lines = receipt?.lines ?? const <ReceiptLine>[];
    final List<ReceiptLine> unresolved = _linesWith(lines, const {LineResolution.unresolved});
    final List<ReceiptLine> settled = _linesWith(
      lines,
      const {LineResolution.matched, LineResolution.created},
    );
    final List<ReceiptLine> rejected = _linesWith(lines, const {LineResolution.rejected});
    final String? failure = _controller?.detailError;
    final String? id = _openId;

    return MSPageScaffold(
      title: Lang.get('screens.receipt.title'),
      // **Neither mode can use `screens.receipt.subtitle`.** It is `:merchant · :date · :count
      // lines` and a photographed receipt has none of the three until extraction runs, so it would
      // render `· · 0 lines`. A receipt that HAS lines states them instead of claiming it has not
      // been read, which is what the preview's thirteen would otherwise say.
      subtitle: receipt == null
          ? null
          : lines.isEmpty
              ? Lang.get('screens.receipt.subtitle_pending')
              : Lang.get('screens.receipt.line_count', {'count': lines.length}),
      actions: _detailActions(),
      children: [
        if (failure != null && id != null) _buildFailure(failure, () => _controller?.open(id)),
        if (receipt != null && lines.isEmpty) _buildNotExtracted(),
        if (receipt != null && lines.isNotEmpty) ...[
          if (unresolved.isNotEmpty) _buildUnresolved(receipt, unresolved),
          _buildSettled(receipt, settled),
          if (rejected.isNotEmpty) _buildRejected(receipt, rejected),
          _buildCommit(settled.length, unresolved.length),
        ],
      ],
    );
  }

  /// The lines in one group.
  ///
  /// Membership is read off `resolution`, which is the server's own answer, rather than derived from
  /// anything this screen can see: a second predicate in Dart is where a group and the state it
  /// claims to show drift apart.
  List<ReceiptLine> _linesWith(List<ReceiptLine> lines, Set<LineResolution> states) =>
      lines.where((ReceiptLine line) => states.contains(line.resolution)).toList(growable: false);

  /// The header controls, which the LIST deliberately does not get: there is nothing to go back to
  /// there, and "take another" reads as a question about which receipt when none is open.
  ///
  /// **Back is an action rather than `MSPageScaffold.backLabel`.** That control calls
  /// `MagicRoute.to(fallback)` and would leave the screen entirely, skipping the list the user came
  /// from. It is labelled with the list's own name, which is the convention the scaffold's own back
  /// affordance uses: the label names the destination.
  List<Widget> _detailActions() {
    return <Widget>[
      // Absent when the caller pinned the screen to one receipt: a preview has no list behind it, so
      // the control would go nowhere.
      if (widget.receipt == null)
        MSButton(
          onPressed: () => setState(() => _openId = null),
          intent: ButtonIntent.ghost,
          className: 'min-h-11 min-w-11 justify-center',
          semanticLabel: Lang.get('screens.receipt.title'),
          child: const WIcon(_backIcon),
        ),
      // **Still unwired, and deliberately not a second copy of the picker.** Retaking means the
      // camera fork plus an upload, which the dashboard's capture button now owns; duplicating that
      // here would be the same twenty lines in two files with one of them left to rot. What it
      // should do instead is replace THIS receipt's document, which needs an endpoint slice 2 owns.
      MSButton(
        onPressed: () {},
        intent: ButtonIntent.ghost,
        className: 'min-h-11 min-w-11 justify-center',
        semanticLabel: Lang.get('screens.receipt.retake'),
        child: const WIcon(_retakeIcon),
      ),
    ];
  }

  /// The lines that need a decision. Leads, and does not fold.
  Widget _buildUnresolved(Receipt receipt, List<ReceiptLine> lines) {
    return SectionCard(
      label: Lang.get('screens.receipt.unresolved_group'),
      count: Lang.get('screens.receipt.line_count', {'count': lines.length}),
      children: [for (final ReceiptLine line in lines) _row(receipt, line)],
    );
  }

  /// The lines that will be committed as they stand.
  ///
  /// Collapsible but open by default. Seventeen rows the user does not have to touch are
  /// still seventeen rows they should be able to check, because the whole review is a
  /// comparison against the paper in their hand. Folding is what they do once satisfied.
  Widget _buildSettled(Receipt receipt, List<ReceiptLine> lines) {
    return SectionCard(
      label: Lang.get('screens.receipt.settled_group'),
      count: Lang.get('screens.receipt.line_count', {'count': lines.length}),
      collapsible: true,
      children: [for (final ReceiptLine line in lines) _row(receipt, line)],
    );
  }

  /// The lines the user dropped, kept visible so the receipt still reconciles.
  Widget _buildRejected(Receipt receipt, List<ReceiptLine> lines) {
    return SectionCard(
      label: Lang.get('screens.receipt.rejected_group'),
      count: Lang.get('screens.receipt.line_count', {'count': lines.length}),
      collapsible: true,
      initiallyExpanded: false,
      children: [for (final ReceiptLine line in lines) _row(receipt, line)],
    );
  }

  /// The commit pair, with the count of what will actually be written.
  Widget _buildCommit(int settled, int unresolved) {
    return WDiv(
      className: 'flex flex-col gap-2 pb-2',
      children: [
        // Naming the number is the point. "Kaydet" alone would hide that four lines are
        // being left behind, and the user would find out by missing stock later.
        WText(
          Lang.get('screens.receipt.will_write', {'settled': settled, 'pending': unresolved}),
          className: 'text-sm text-fg-muted',
        ),
        MSButton(
          onPressed: () {},
          fullWidth: true,
          className: 'justify-center',
          child: WText(Lang.get('screens.receipt.submit', {'count': settled})),
        ),
        MSButton(
          onPressed: () {},
          intent: ButtonIntent.ghost,
          fullWidth: true,
          className: 'justify-center',
          child: WText(Lang.get('screens.receipt.discard')),
        ),
      ],
    );
  }

  /// One extracted line.
  ///
  /// **The row takes strings the model does not carry, and composing them here is the point.**
  /// `formatted` goes through `ProductListItem.format` and `price` through `moneyLabel`, both of
  /// which read the active locale; a model holding either would be a formatted string on the wire.
  ///
  /// The unit falls back to the code the document printed when the server could not map it (D97): an
  /// unrecognised unit is a state the screen shows rather than a default it hides, and `unitLabel`
  /// passes an unknown code through as it stands.
  ///
  /// **No location, and none can be invented.** `receipt_lines` carries `product_id` and
  /// `global_product_id` and no location column, so the chip the drawn screen has would be a
  /// suggestion nothing computes.
  ///
  /// **No tap either.** Resolving a line is slice 3; a row that responds and does nothing is worse
  /// than one that does not respond, because the user reads the first as the app failing.
  Widget _row(Receipt receipt, ReceiptLine line) {
    final num amount = line.quantity ?? 0;
    final num? total = line.lineTotal;

    return ReceiptLineRow(
      extracted: line.rawName,
      productName: line.productName,
      resolution: line.resolution,
      amount: amount,
      formatted: ProductListItem.format(amount),
      unit: line.resolvedUnit ?? line.rawUnitCode,
      price: total == null ? null : moneyLabel(total, receipt.currency),
    );
  }

  /// A receipt nothing has been read off yet, which in this slice is every receipt.
  ///
  /// Not an empty error: the photograph is stored and the reading has not happened. Saying so is the
  /// difference between "the app has not got to this yet" and "this receipt came out blank".
  Widget _buildNotExtracted() {
    return SectionCard(
      children: [
        // Full width so MSEmptyState's own `items-center` has something to centre in.
        WDiv(
          className: 'w-full',
          child: MSEmptyState(
            icon: _pendingIcon,
            title: Lang.get('screens.receipt.not_extracted'),
          ),
        ),
      ],
    );
  }

  /// No receipts at all, which is where every tenant starts.
  Widget _buildEmpty() {
    return SectionCard(
      children: [
        WDiv(
          className: 'w-full',
          child: MSEmptyState(
            icon: _emptyIcon,
            title: Lang.get('screens.receipt.empty'),
          ),
        ),
      ],
    );
  }

  /// A request that did not come back, in the card slot every screen here uses for one.
  Widget _buildFailure(String message, VoidCallback onRetry) {
    return SectionCard(error: message, onRetry: onRetry, children: const []);
  }
}
