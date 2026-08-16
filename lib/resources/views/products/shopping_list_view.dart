import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import '../../../ui/layouts/app_page_scaffold.dart';
import 'package:magic_starter/magic_starter.dart'
    show MSButton, ButtonIntent, MSEmptyState;

import '../../../app/controllers/shopping_controller.dart';
import '../../../app/models/shopping_line.dart';
import '../../../app/support/plural.dart';
import '../../../app/support/unit_label.dart';
import '../../../ui/components/section_card/section_card.dart';
import '../../../ui/components/shopping_row/shopping_row.dart';
import 'shopping_add_sheet.dart';

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
class ShoppingListView extends StatefulWidget {
  /// Lines supplied by the caller, which is how the preview catalog stays offline.
  ///
  /// Null means "read [ShoppingController]", which is what the route does. The state class only
  /// touches the controller when this is null, so previewing this screen issues no request.
  final List<ShoppingLine>? lines;

  /// Creates the [ShoppingListView], reading from [ShoppingController].
  const ShoppingListView({super.key, this.lines});

  /// Creates the view with nothing to buy.
  const ShoppingListView.empty({super.key}) : lines = const <ShoppingLine>[];

  @override
  State<ShoppingListView> createState() => _ShoppingListViewState();
}

class _ShoppingListViewState extends State<ShoppingListView> {
  static const IconData _addIcon = Icons.add;
  static const IconData _receiptIcon = Icons.receipt_long_outlined;
  static const IconData _emptyIcon = Icons.shopping_basket_outlined;

  /// The controller, or null when the caller supplied its own lines.
  ShoppingController? _controller;

  @override
  void initState() {
    super.initState();

    if (widget.lines != null) return;

    final ShoppingController controller = ShoppingController.instance
      ..addListener(_onControllerChanged);

    // `Magic.findOrPut` registers the instance and nothing calls `onInit` for a plain
    // `StatefulWidget`, so without this the screen says there is nothing to buy.
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

  List<ShoppingLine> get _all => widget.lines ?? _controller?.lines ?? const <ShoppingLine>[];

  /// Whether there is an answer, as opposed to no answer YET.
  ///
  /// The empty list is not a failure state and must not read as one: it means nothing is running
  /// out, which is the outcome the whole forecasting feature exists to produce. Which also makes it
  /// the one thing this screen must not say while the request is still in flight.
  bool get _hasAnswer => widget.lines != null || (_controller?.loaded ?? false);

  List<ShoppingLine> get _pending =>
      _all.where((ShoppingLine l) => !l.isChecked).toList(growable: false);

  List<ShoppingLine> get _checked =>
      _all.where((ShoppingLine l) => l.isChecked).toList(growable: false);

  @override
  Widget build(BuildContext context) {
    final bool anything = _hasAnswer && _all.isNotEmpty;

    return AppPageScaffold(
      title: Lang.get('screens.shopping.title'),
      subtitle: anything
          ? Lang.get('screens.shopping.subtitle', {
              'pending': _pending.length,
              'checked': _checked.length,
            })
          : Lang.get('screens.shopping.subtitle_empty'),
      // Pinned rather than trailing (D70): a shopping list is as long as the shop, so the
      // actions that finish it cannot live at the end of it.
      footer: _buildActions(),
      children: anything
          ? [if (_pending.isNotEmpty) _buildPending(), if (_checked.isNotEmpty) _buildChecked()]
          : [if (_hasAnswer) _buildEmpty()],
    );
  }

  /// What is left to get, urgency first.
  Widget _buildPending() {
    return SectionCard(
      label: Lang.get('screens.shopping.pending_group'),
      count: plural('screens.shopping.product_count', _pending.length, {'count': _pending.length}),
      children: [for (final ShoppingLine line in _pending) _buildRow(line)],
    );
  }

  /// What is in the trolley. Collapsible, because it only grows.
  Widget _buildChecked() {
    return SectionCard(
      label: Lang.get('screens.shopping.checked_group'),
      count: plural('screens.shopping.product_count', _checked.length, {'count': _checked.length}),
      collapsible: true,
      children: [for (final ShoppingLine line in _checked) _buildRow(line)],
    );
  }

  /// One line.
  ///
  /// **`reasonDetail` is composed on the model, from evidence the server sent** (D98). Nothing here
  /// decides what a line may claim: the payload already withheld the figure a tier is not allowed,
  /// so the shape of the sentence is settled before it reaches a widget.
  Widget _buildRow(ShoppingLine line) {
    return ShoppingRow(
      name: line.name,
      amount: line.quantity,
      formatted: line.formatted,
      unit: unitLabel(line.unit, line.quantity),
      reason: line.reason,
      reasonDetail: line.reasonDetail,
      isChecked: line.isChecked,
      // Optimistic, because the user is standing in a shop tapping down a list and a round trip
      // per tap would make the screen feel like it is arguing with them. A tick is NOT a stock
      // movement (D47): the receipt below is what closes that loop.
      onToggle: () => _controller?.toggle(line),
    );
  }

  /// Ask what to add, and add it.
  ///
  /// The list is not a catalogue: what the user types creates no product (D100), so the sheet asks
  /// for words and a number rather than offering a picker. Nothing is written when it is dismissed.
  Future<void> _add() async {
    final ShoppingAddDraft? draft = await ShoppingAddSheet.show(context);

    if (draft == null) return;

    final String? failure = await _controller?.add(draft.name, draft.quantity);

    if (failure == null || !mounted) return;

    MagicFeedback.error(Lang.get('screens.shopping.add_title'), failure);
  }

  /// Nothing to buy, which is the good outcome and has to read like one.
  Widget _buildEmpty() {
    return SectionCard(
      label: Lang.get('screens.shopping.pending_group'),
      children: [
        WDiv(
          // Full width so MSEmptyState's own `items-center` has something to centre in.
          className: 'w-full',
          child: MSEmptyState(
            icon: _emptyIcon,
            title: Lang.get('screens.shopping.empty_title'),
            // Says the mechanism rather than apologising for the blank: a product appears
            // here once it has a target level or enough history to run one.
            description:
                Lang.get('screens.shopping.empty_description'),
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
          onPressed: _add,
          intent: ButtonIntent.ghost,
          fullWidth: true,
          className: 'justify-center',
          child: WDiv(
            className: 'flex flex-row items-center justify-center gap-2',
            children: [
              const WIcon(_addIcon, className: 'size-4'),
              WText(Lang.get('screens.shopping.empty_action')),
            ],
          ),
        ),
        // Appears only once something is in the trolley, because that is when it means
        // anything. Absent rather than disabled: a disabled primary button is visually
        // indistinguishable from a live one in this theme, measured.
        if (_checked.isNotEmpty) ...[
          WText(Lang.get('screens.shopping.receipt_hint'), className: 'text-xs text-fg-muted'),
          MSButton(
            // The receipt review screen exists and this is its natural entry: the user has just
            // come back from the shop with the things on this list, which is exactly when a
            // receipt is in their hand. It was the last dead link between two screens that both
            // already existed.
            onPressed: () => MagicRoute.to('/receipt'),
            fullWidth: true,
            className: 'justify-center',
            child: WDiv(
              className: 'flex flex-row items-center justify-center gap-2',
              children: [
                const WIcon(_receiptIcon, className: 'size-4'),
                WText(Lang.get('screens.shopping.receipt_action')),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
