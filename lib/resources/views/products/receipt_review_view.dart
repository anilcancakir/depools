import 'dart:async';

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart'
    show ButtonIntent, MSBottomSheet, MSButton, MSEmptyState, MSPageScaffold;

import '../../../app/controllers/receipt_controller.dart';
import '../../../app/models/receipt.dart';
import '../../../app/support/date_label.dart';
import '../../../app/support/money_label.dart';
import '../../../app/support/plural.dart';
import '../../../ui/components/option_row/option_row.dart';
import '../../../ui/components/quantity/quantity.dart';
import '../../../ui/components/receipt_line_row/receipt_line_row.dart';
import '../../../ui/components/section_card/section_card.dart';
import 'destination_sheet.dart';
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
  static const IconData _backIcon = Icons.arrow_back;
  static const IconData _emptyIcon = Icons.receipt_long_outlined;
  static const IconData _pendingIcon = Icons.hourglass_empty;

  /// The controller, or null when the caller supplied its own data.
  ReceiptController? _controller;

  /// The sentence from the last action the user started, as opposed to the last fetch.
  ///
  /// Held apart from the controller's own `detailError` because they fail for different reasons and
  /// clear at different moments: a fetch failure is retried by refetching, and this one is cleared
  /// by the next attempt at the same action.
  String? _actionError;

  /// Which receipt the user opened, or null while the list is showing.
  String? _openId;

  /// Whether a commit is in flight.
  bool _committing = false;

  /// The shelves a commit can write to.
  ///
  /// Fetched here rather than held by the controller, the same way `barcode_scan_view` fetches its
  /// own: two screens is not three, and the third caller is when this becomes a shared reader.
  List<DestinationOption> _locations = const <DestinationOption>[];

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

    unawaited(_loadLocations());
  }

  /// Reads the shelves the commit can write to.
  ///
  /// A commit needs a location and `receipt_lines` carries none: the paper does not say where the
  /// shopping went, so the user says it once for the whole receipt rather than per line.
  Future<void> _loadLocations() async {
    final dynamic response = await Http.get('/locations');

    if (!mounted) return;

    final dynamic rows = response.successful ? response['data'] : null;

    setState(() {
      _locations = <DestinationOption>[
        if (rows is List)
          for (final dynamic row in rows)
            if (row is Map && row['id'] is String)
              DestinationOption(
                id: row['id'] as String,
                name: (row['name'] as String?) ?? '',
                fullPath: (row['full_path'] as String?) ?? (row['name'] as String?) ?? '',
                depth: (row['depth'] as num?)?.toInt() ?? 0,
                productCount: (row['stock_count'] as num?)?.toInt() ?? 0,
              ),
      ];
    });
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
    final num? total = receipt.totalAmount;
    final int lines = receipt.linesCount ?? receipt.lines.length;
    final String label = _identity(receipt);

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

  /// What to call this receipt, for a list row and for the header of its own screen.
  ///
  /// **The date branch is the normal path rather than a fallback.** `supplier_name` and `issued_on`
  /// are null on every receipt this slice can produce, so a label reading the supplier alone would
  /// render the whole list blank. The third branch is unreachable through the API, which always sends
  /// `created_at`, and names the state rather than inventing a date for a payload that could not be
  /// read.
  ///
  /// One function for both places so a receipt cannot be called one thing in the list and another on
  /// its own screen, which is the confusion a user hits at exactly the moment they are checking they
  /// opened the right one.
  String _identity(Receipt receipt) {
    final String? supplier = receipt.supplierName;
    final DateTime? created = receipt.createdAt;

    if (supplier != null) return supplier;

    return created == null
        ? Lang.get('screens.receipt.status_pending')
        : Lang.get('screens.receipt.uploaded_at', {'date': dateLabel(created)});
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
      //
      // **With no lines the subtitle IDENTIFIES the receipt rather than restating its state.** The
      // card below already says "not read yet", and the first browser pass showed the two stacked:
      // the same four words twice on one screen, on the only screen where every receipt looks
      // identical. Which receipt is open is the thing the header was failing to answer, and it is
      // the same label the list row carries, so tapping a row no longer changes what it is called.
      subtitle: receipt == null
          ? null
          : lines.isEmpty
              ? _identity(receipt)
              : Lang.get('screens.receipt.line_count', {'count': lines.length}),
      actions: _detailActions(),
      children: [
        if (failure != null && id != null) _buildFailure(failure, () => _controller?.open(id)),
        // The action's own failure, separate from the fetch's: retrying it means starting the action
        // again rather than refetching the receipt, and the two would otherwise share one retry
        // button that did the wrong one of them.
        if (_actionError != null && receipt != null)
          _buildFailure(_actionError!, () => _extract(receipt)),
        if (receipt != null && lines.isEmpty) _buildNotExtracted(receipt),
        if (receipt != null && lines.isNotEmpty) ...[
          if (unresolved.isNotEmpty) _buildUnresolved(receipt, unresolved),
          _buildSettled(receipt, settled),
          if (rejected.isNotEmpty) _buildRejected(receipt, rejected),
          _buildCommit(receipt, settled, unresolved.length),
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
      // **No retake control, rather than one that does nothing.** The drawn screen has it and it
      // shipped here with an empty callback, which is the failure this file's own `_row` docblock
      // already names for a tap: a control that responds and does nothing reads as the app failing,
      // which is worse than one that is not offered. Retaking means replacing THIS receipt's
      // document, and the endpoint for that is slice 2's; wiring it to the dashboard's picker instead
      // would upload a SECOND receipt, which is a different thing wearing the same word. The button
      // comes back with the endpoint. `screens.receipt.retake` stays in both catalogues for it.
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
  ///
  /// **The count is of WRITABLE lines, not of settled ones.** A settled line still needs a product
  /// and a quantity to become stock, and a line whose quantity the extraction could not read has
  /// neither: counting it here would promise a write that then silently does not happen, which is
  /// the failure mode this screen exists to prevent.
  ///
  /// **No discard control, rather than one that does nothing.** The drawn screen has it and it
  /// shipped on an empty callback, which is the same failure this file's `_row` docblock names for a
  /// tap. Discarding means deleting the receipt and its document, an endpoint that does not exist
  /// and an authorization surface with no test; `screens.receipt.discard` stays in both catalogues
  /// for when it does.
  Widget _buildCommit(Receipt receipt, List<ReceiptLine> settled, int unresolved) {
    final Map<String, ReceiptLineDecision> writable = _writable(settled);
    final bool busy = _committing;

    return WDiv(
      className: 'flex flex-col gap-2 pb-2',
      children: [
        // Naming the number is the point. "Kaydet" alone would hide that four lines are
        // being left behind, and the user would find out by missing stock later.
        WText(
          Lang.get('screens.receipt.will_write', {
            'settled': writable.length,
            'pending': unresolved,
          }),
          className: 'text-sm text-fg-muted',
        ),
        MSButton(
          onPressed: busy || writable.isEmpty ? null : () => _commit(receipt, writable),
          disabled: busy || writable.isEmpty,
          fullWidth: true,
          className: 'justify-center',
          child: WText(
            Lang.get(
              busy ? 'screens.receipt.committing' : 'screens.receipt.submit',
              {'count': writable.length},
            ),
          ),
        ),
      ],
    );
  }

  /// The settled lines that can actually become stock, keyed by line id.
  ///
  /// A line needs both halves: the product it resolved to, and a quantity the paper gave. Either
  /// missing means the row is evidence rather than an instruction, and it stays on screen unwritten.
  Map<String, ReceiptLineDecision> _writable(List<ReceiptLine> settled) {
    return <String, ReceiptLineDecision>{
      for (final ReceiptLine line in settled)
        if (line.productId != null && line.quantity != null)
          line.id: ReceiptLineDecision(productId: line.productId!, quantity: line.quantity!),
    };
  }

  /// Asks where the shopping went, then writes it.
  ///
  /// **The location is asked for once per receipt, not per line.** The paper does not say where the
  /// shopping was put away and `receipt_lines` has no location column, so a per-line picker would be
  /// twenty-two questions with the same answer.
  Future<void> _commit(Receipt receipt, Map<String, ReceiptLineDecision> writable) async {
    final String? locationId = await _pickDestination();

    if (locationId == null || !mounted) return;

    setState(() {
      _committing = true;
      _actionError = null;
    });

    final String? failure = await _controller?.commit(
      receipt.id,
      locationId: locationId,
      accepted: writable,
      // **Keyed on the receipt, and stable across a partial commit.** The server splits it per line,
      // so coming back to finish the remaining lines reuses this key harmlessly: the lines already
      // written collide on their own keys and the new ones do not exist yet.
      batchKey: 'receipt-${receipt.id}',
    );

    if (!mounted) return;

    setState(() {
      _committing = false;
      _actionError = failure;
    });
  }

  /// Opens the shelf picker and answers what it returns.
  ///
  /// The `Builder`-free shape `barcode_scan_view` uses, including the reason the sheet is its own
  /// widget: the search field's state belongs to it, so a `setState` here while it is open would
  /// rebuild the receipt behind it.
  Future<String?> _pickDestination() {
    return MSBottomSheet.show<String>(
      context,
      title: Lang.get('screens.receipt.pick_destination_title'),
      body: DestinationSheet(
        options: _locations,
        recentIds: const <String>[],
      ),
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
    final num? quantity = line.quantity;
    final num? total = line.lineTotal;

    return ReceiptLineRow(
      extracted: line.rawName,
      productName: line.productName,
      resolution: line.resolution,
      // **A quantity the extraction could not read is NOT zero, and printing `0` says it was.**
      // `quantity` is nullable for exactly that case, and a line reading "0 kg" claims the paper
      // said none rather than that the app could not tell, which is the difference between a receipt
      // the user can check and one they have to distrust. The row still gets 0 as the raw `amount`,
      // because that drives its zero TONE and an unreadable quantity is not a quantity to celebrate.
      amount: quantity ?? 0,
      formatted: quantity == null
          ? Lang.get('screens.receipt.quantity_unknown')
          : ProductListItem.format(quantity),
      unit: line.resolvedUnit ?? line.rawUnitCode,
      price: total == null ? null : moneyLabel(total, receipt.currency),
    );
  }

  /// A receipt nothing has been read off yet, and the control that reads it.
  ///
  /// Not an empty error: the photograph is stored and the reading has not happened. Saying so is the
  /// difference between "the app has not got to this yet" and "this receipt came out blank".
  ///
  /// **The read is a tap rather than something that happens on arrival.** It spends one of the
  /// tenant's AI credits, and an action that costs the user something is theirs to start. It also
  /// takes seconds, so the button carries a label while it runs rather than leaving the card looking
  /// idle.
  ///
  /// A receipt that comes back with nothing lands here again, which is correct: extraction stopping
  /// (no credits, an unreadable photograph) leaves the manual path open, and this is that path's
  /// starting point rather than an error state.
  Widget _buildNotExtracted(Receipt receipt) {
    final bool busy = _controller?.extracting ?? false;

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
        MSButton(
          onPressed: busy ? null : () => _extract(receipt),
          disabled: busy,
          fullWidth: true,
          className: 'justify-center',
          child: WText(
            Lang.get(busy ? 'screens.receipt.extracting' : 'screens.receipt.extract'),
          ),
        ),
      ],
    );
  }

  /// Reads the receipt, keeping the server's own sentence when it refuses.
  Future<void> _extract(Receipt receipt) async {
    final String? failure = await _controller?.extract(receipt.id);

    if (!mounted) return;

    setState(() => _actionError = failure);
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
