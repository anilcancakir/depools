import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart'
    show
        MSPageScaffold,
        MSButton,
        ButtonIntent,
        ButtonSize,
        MSDropdownMenu,
        ConfirmDialogVariant,
        MSDropdownMenuItem,
        MagicStarterConfirmDialog,
        MSEmptyState;

import '../../../app/controllers/product_detail_controller.dart';
import '../../../ui/components/draft_field/draft_field.dart';
import '../../../ui/components/expiry_badge/expiry_badge.dart';
import '../../../ui/components/location_stock_row/location_stock_row.dart';
import '../../../ui/components/lot_row/lot_row.dart';
import '../../../ui/components/product_row/product_row.dart';
import '../../../ui/components/movement_row/movement_row.dart';
import '../../../ui/components/quantity/quantity.dart';
import '../../../ui/components/section_card/section_card.dart';
import '../../../ui/components/serial_row/serial_row.dart';
import '../../../ui/components/stat_card/stat_card.dart';
import '../../../ui/components/tag/index.dart';
import 'field_editor_sheet.dart';
import 'product_filter_sheet.dart';
import 'product_fixtures.dart';
import 'stock_in_sheet.dart';
import 'stock_move_sheet.dart';
import 'stock_out_sheet.dart';

/// Product detail: everything known about one product the tenant holds.
///
/// This is the screen the data model was designed for, so it is deliberately built
/// against the hard case. A product with two units in one place teaches nothing;
/// this shows stock split across two nested locations, four lots with four different
/// dates including one already expired and one depleted, a movement history mixing
/// purchase, consumption, waste and a correction, and a forecast that has to admit
/// it does not have enough history yet.
///
/// Reading order, top to bottom, follows what a user came for:
///
/// 1. **What is it.** Image, name, brand, category, tags, barcodes, description.
///    Identity first, because a user arriving from a scan or a search needs to
///    confirm they are looking at the right thing before any number means anything.
/// 2. **How much do I have.** The total leads, at `lg`.
/// 3. **Where is it.** Split per location rather than summed, since "3 in the fridge,
///    2 in the pantry" is the answer and a total of 5 hides it.
/// 4. **What is about to go bad.** Lots, earliest first.
/// 5. **What happened.** The ledger.
///
/// **Where an action goes, and why it is a rule rather than a case-by-case call.**
/// An earlier version had no rule and it showed: adding a barcode sat in a card
/// header while adding stock sat in a page footer, even though both add to a
/// collection. Nothing explained the difference, so the next screen would have
/// invented its own placement.
///
/// - **A card header's right side is for NAVIGATION only.** "Tümü" belongs there
///   because it takes you elsewhere, and it carries a chevron so it reads that way.
///   Nothing that changes data goes in a card header.
/// - **The page footer is for the FREQUENT mutations.** Stock out and stock in, done
///   many times a day, sized as real buttons.
/// - **The header overflow is for the RARE mutations.** Adding a barcode, editing,
///   archiving. Reachable, not competing.
///
/// A consequence worth noting: most cards end up with no action at all, and that is
/// correct. "Partiler" does not need one because a lot is created by the stock-in
/// button, and "Konumlar" does not because moving stock is in the header. Giving
/// every card a button for symmetry would leave the two that mean something
/// indistinguishable from the ones that do not.
///
/// Currently rendered from the fixtures below rather than a controller. Wiring it to
/// a `ProductController` is the next step; the fixtures stay afterwards as the
/// preview's data source so the catalog keeps working without a backend.
@immutable
class ProductShowView extends StatefulWidget {

  /// Whether this product has no stock and no history yet.
  ///
  /// A product exists before any stock does: it is created by a scan, a receipt line
  /// or by hand, and the first movement can come minutes or days later. So the empty
  /// shape is a normal state, not an error, and it is the first thing a new user sees
  /// after adding their first product. `.claude/rules/design.md` requires a designed
  /// empty state with a call to action rather than a bare card.
  ///
  /// It has to reach EVERY number on the screen, not only the collection cards. A
  /// first pass made the lot, location and movement lists empty and left the total at
  /// "5 adet" with an expired badge and "9 hareket" beside it, so the screen
  /// contradicted itself: a product with no movements cannot have stock, an expiry or
  /// a waste figure. Anything derived from the ledger has to go to zero together.
  final bool isNew;

  /// Which fixture to render. Defaults to the lot-tracked milk.
  final TrackingMode mode;

  /// The product id from the route, or null in the preview catalog.
  final String? id;

  /// A product supplied by the caller, which is how the catalog stays offline.
  ///
  /// Null means "read [ProductDetailController] for [id]". The preview passes a fixture, and the
  /// state class only touches the controller when this is null, so previewing cannot fire a request.
  final ProductListItem? item;

  /// Creates the [ProductShowView].
  const ProductShowView({super.key, this.id, this.item})
    : isNew = false,
      mode = TrackingMode.lot;

  /// Creates the view for a product that has no stock or history yet.
  const ProductShowView.newProduct({super.key, this.item})
    : id = null,
      isNew = true,
      mode = TrackingMode.lot;

  /// Creates the view for a serial-tracked product (D28).
  ///
  /// A separate entry point rather than a parameter on the default one, because the
  /// serial case has to be REVIEWABLE. Half this design only exists on this path, and
  /// a variant reachable only by editing a fixture is a variant nobody looks at.
  const ProductShowView.serialTracked({super.key, this.item})
    : id = null,
      isNew = false,
      mode = TrackingMode.serial;

  @override
  State<ProductShowView> createState() => _ProductShowViewState();
}

class _ProductShowViewState extends State<ProductShowView> {
  static const IconData _imagePlaceholderIcon = Icons.photo_outlined;
  static const IconData _moveIcon = Icons.swap_horiz_outlined;
  static const IconData _labelIcon = Icons.qr_code_2_outlined;
  static const IconData _moreIcon = Icons.more_horiz_outlined;
  static const IconData _outIcon = Icons.remove_outlined;
  static const IconData _inIcon = Icons.add_outlined;
  static const IconData _chevronIcon = Icons.chevron_right_outlined;
  static const IconData _emptyLotsIcon = Icons.inventory_2_outlined;
  static const IconData _emptyMovementsIcon = Icons.history_outlined;

  /// Null in the preview, where [ProductShowView.item] supplies the product instead.
  ProductDetailController? _controller;

  @override
  void initState() {
    super.initState();

    final String? id = widget.id;
    if (widget.item != null || id == null) return;

    // `load` rather than `onInit`, because the id is a parameter rather than a fixed collection:
    // `onInit` takes no arguments and only `MagicView` calls it anyway. The controller's own guard
    // makes a second visit to the same product free.
    _controller = ProductDetailController.instance..addListener(_onControllerChanged);
    _controller!.load(id);
  }

  /// Reloads when the ROUTE changes under a reused State.
  ///
  /// Flutter matches by widget type, so navigating from one product to another can hand this same
  /// State a new `id` without calling `initState` again. Without this the screen keeps drawing the
  /// previous product, which is the worst shape of stale: everything renders, nothing errors, and
  /// the numbers belong to something else.
  @override
  void didUpdateWidget(ProductShowView oldWidget) {
    super.didUpdateWidget(oldWidget);

    final String? id = widget.id;
    // The same refusal `initState` makes, and for the same reason: a supplied item is the caller
    // saying "draw this", so the controller stays untouched and no request is issued. The previews
    // pass no id at all, so they were already covered; this keeps the two paths from diverging if a
    // caller ever passes both.
    if (widget.item != null || id == null || id == oldWidget.id) return;

    _controller ??= ProductDetailController.instance..addListener(_onControllerChanged);
    _controller!.load(id);
  }

  @override
  void dispose() {
    _controller?.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  /// The product to draw, or null while it is being fetched.
  ///
  /// The fixture fallback is gone from here: this screen used to pick one out of
  /// [productFixtures] by tracking mode, which was the right call while nothing could hand it a
  /// product and is a second source of truth now that something can. The catalog passes the
  /// fixture in through [ProductShowView.item] instead, which keeps the previews rendering the
  /// same rows the list previews do.
  ProductListItem? get _resolved => widget.item ?? _controller?.rxState;

  /// The product, after [build] has established there is one.
  ProductListItem get _product => _resolved!;

  /// Opens the stock-out sheet and writes what it returns, FEFO deciding the lots.
  ///
  /// The location comes from the chosen LOT rather than from a picker: the sheet opens with a lot
  /// already selected by FEFO, and that lot is somewhere. A serial-tracked product answers through
  /// its unit instead, which is the same fact reached the other way.
  ///
  /// Two of the sheet's four reasons are not writable here, and refusing them out loud is the point.
  /// A stock-take correction and a data correction can both be POSITIVE, so they are not outflows
  /// and `StockWriter::consume` refuses them by design; the count screen owns that path. Sending
  /// them anyway would produce a 422 that reads like a bug.
  Future<void> _consumeStock() async {
    final ProductListItem product = _product;
    final ProductDetailController? controller = _controller;

    final StockOutDraft? draft = await StockOutSheet.show(context, product: product);
    if (draft == null || controller == null) return;

    final String? productId = product.id;
    final String? locationId = draft.lot?.locationId ?? draft.serial?.locationId;
    if (productId == null || locationId == null) return;

    final String? reason = switch (draft.reason) {
      StockOutReason.consumption => 'consumption',
      StockOutReason.waste => 'waste',
      StockOutReason.stockTake || StockOutReason.correction => null,
    };

    if (reason == null) {
      MagicFeedback.error(
        Lang.get('screens.stock_out.title'),
        Lang.get('screens.stock_out.correction_elsewhere'),
      );

      return;
    }

    final String? failure = await controller.consume(
      productId: productId,
      locationId: locationId,
      quantity: draft.amount,
      reason: reason,
    );

    _report(failure, Lang.get('screens.stock_out.title'), Lang.get('screens.stock_out.done'));
  }

  /// Opens the move sheet and writes the transfer, which is ONE call rather than two.
  ///
  /// A transfer is a pair of movements the writer appends together. Splitting it into an out and an
  /// in client-side would leave a window where the stock is in neither place, and a failure halfway
  /// would leave it there permanently.
  Future<void> _moveStock() async {
    final ProductListItem product = _product;
    final ProductDetailController? controller = _controller;

    final StockMoveDraft? draft = await StockMoveSheet.show(
      context,
      product: product,
      locations: _controllerLocations(),
    );

    if (draft == null || controller == null) return;

    final String? productId = product.id;
    if (productId == null) return;

    final String? failure = await controller.transfer(
      productId: productId,
      fromLocationId: draft.fromLocationId,
      toLocationId: draft.toLocationId,
      quantity: draft.amount,
    );

    _report(failure, Lang.get('screens.stock_move.title'), Lang.get('screens.stock_move.done'));
  }

  /// The tenant's locations as filter options, or null in the preview.
  List<FilterOption>? _controllerLocations() {
    final ProductDetailController? controller = _controller;
    if (controller == null) return null;

    return <FilterOption>[
      for (final MapEntry<String, String> entry in controller.locationPaths.entries)
        FilterOption(id: entry.key, label: entry.value, path: entry.value),
    ];
  }

  /// One toast for all three writes: the server's sentence on failure, the confirmation otherwise.
  void _report(String? failure, String title, String success) {
    if (failure == null) {
      MagicFeedback.success(title, success);

      return;
    }

    MagicFeedback.error(title, failure);
  }

  /// Opens the stock-in sheet, and actually writes what it returns.
  ///
  /// The draft was DISCARDED before this: the sheet opened, the user filled it in, and the result
  /// went nowhere. So the ledger had never been written from the UI at all, on the screen whose two
  /// footer buttons are the product's core promise.
  ///
  /// The sheet is given the tenant's real locations, and on success the controller reloads, so the
  /// batches and the total on screen come from the ledger rather than from an optimistic guess. An
  /// optimistic update would be the wrong instinct here specifically: FEFO decides which lot a
  /// consumption comes out of and the server is the only thing that knows, so a client that
  /// predicted the result would eventually disagree with the ledger it is supposed to be showing.
  Future<void> _receiveStock() async {
    final ProductListItem product = _product;
    final ProductDetailController? controller = _controller;

    final StockInDraft? draft = await StockInSheet.show(
      context,
      product: product,
      locations: _controllerLocations(),
    );

    if (draft == null || controller == null) return;

    final String? productId = product.id;
    if (productId == null) return;

    final String? failure = await controller.receive(
      productId: productId,
      locationId: draft.locationId,
      quantity: draft.amount,
      expiresAt: draft.expiresAt,
    );

    _report(failure, Lang.get('screens.stock_in.title'), Lang.get('screens.stock_in.done'));
  }

  /// The screen before its product has arrived, or after the fetch failed.
  ///
  /// A scaffold with no title rather than the product's name, because the name is exactly what is
  /// not known yet. `SectionCard`'s own `error` plus `onRetry` pair carries the failure, the same
  /// way the list screen does, so there is one error panel in the app rather than two.
  Widget _buildPending() {
    final bool failed = _controller?.isError ?? false;

    return MSPageScaffold(
      title: Lang.get('screens.products.title'),
      children: [
        SectionCard(
          label: Lang.get('screens.products.detail_title'),
          error: failed ? _controller?.rxStatus.message : null,
          onRetry: failed && widget.id != null
              ? () => _controller?.load(widget.id!, force: true)
              : null,
          // `ProductRow.skeleton()` is the only skeleton the library has, and it is the right
          // shape here: the first card on this screen is the product's identity, which is what a
          // row draws. A second skeleton component for one card would be a component nobody else
          // uses.
          children: failed ? const <Widget>[] : <Widget>[const ProductRow.skeleton()],
        ),
      ],
    );
  }

  /// The location's full path, from the controller when there is one.
  ///
  /// Falls back to the fixture lookup so the preview keeps naming its locations, and to the raw id
  /// so a location the payload did not describe still heads its own section rather than vanishing.
  String _locationPath(String locationId) =>
      _controller?.locationPaths[locationId] ?? resolveLocationPath(locationId) ?? locationId;


  @override
  Widget build(BuildContext context) {
    // Guarded FIRST, because everything below reads `_product` and it is null until the fetch
    // lands. The title is part of the chrome rather than the body, so this cannot be a branch
    // inside the page: without a product there is nothing to name the screen after either.
    if (_resolved == null) return _buildPending();

    return MSPageScaffold(
      title: _product.name,
      subtitle: _product.brand,
      // "Taşı" and "Etiket" live in the header rather than beside the primary button
      // at the bottom. Three buttons in one row does not fit a phone, and it left the
      // screen with no clear primary. As icons in the header they stay reachable
      // without competing, and each carries a `semanticLabel` because an icon-only
      // control is nameless to a screen reader otherwise.
      actions: [
        MSButton(
          // Disabled with nothing on hand: a move needs a source that holds something, and
          // the sheet's own source list would be empty.
          onPressed: _product.amount == 0
              ? null
              : _moveStock,
          disabled: _product.amount == 0,
          intent: ButtonIntent.ghost,
          className: 'min-h-11 min-w-11 justify-center',
          semanticLabel: Lang.get('screens.product.action_move'),
          child: const WIcon(_moveIcon),
        ),
        MSButton(
          onPressed: () {},
          intent: ButtonIntent.ghost,
          className: 'min-h-11 min-w-11 justify-center',
          semanticLabel: Lang.get('screens.product.action_label'),
          child: const WIcon(_labelIcon),
        ),
        MSDropdownMenu(
          items: [
            MSDropdownMenuItem(label: Lang.get('screens.product.action_barcode'), onTap: () {}),
            // The label sheet belongs to the product it labels, not to a global menu, which is
            // why `LabelPrintView` had no way in until this line existed.
            MSDropdownMenuItem(
              label: Lang.get('screens.product.action_labels'),
              onTap: () => MagicRoute.to('/etiket'),
            ),
            // No `Düzenle` entry. Editing is field by field from the rows below, through
            // `FieldEditorSheet`, which is the pattern `ai-enrichment.md` already describes and the
            // draft screen already uses. A second whole-record form would be the same job in two
            // places and the user would have to learn which one lives where.
            // **Archiving asks first.** It removes a record that carries history and movements
            // from every list the user knows, and although it is a soft delete the user has no way
            // to know that. The dialog says what survives, which is the part that makes the answer
            // easy rather than the part that makes it scary.
            MSDropdownMenuItem(
              label: Lang.get('screens.product.action_archive'),
              onTap: () => MagicStarterConfirmDialog.show(
                context,
                title: Lang.get('screens.product.archive_title'),
                description: Lang.get('screens.product.archive_description'),
                confirmLabel: Lang.get('screens.product.archive_confirm'),
                variant: ConfirmDialogVariant.danger,
              ),
            ),
          ],
          child: MSButton(
            // Null on purpose, and NOT disabled: MSDropdownMenu owns the gesture and
            // this button is only its trigger's appearance. Passing `disabled: true`
            // here would grey out a control that works.
            onPressed: null,
            intent: ButtonIntent.ghost,
            className: 'min-h-11 min-w-11 justify-center',
            semanticLabel: Lang.get('screens.product.action_more'),
            child: const WIcon(_moreIcon),
          ),
        ),
      ],
      children: [
        _buildIdentity(),
        _buildDetails(context),
        _buildBarcodes(),
        _buildStockSummary(),
        _buildForecast(),
        _buildLocations(),
        _buildLots(),
        _buildMovements(),
        _buildPrimaryAction(context),
      ],
    );
  }

  /// Image, category, tags and description: what the thing actually is.
  ///
  /// The image is a placeholder here because the fixture carries no asset. In the
  /// wired screen it is the product photo, and it earns its space: a user who
  /// scanned a barcode confirms the match by looking, not by reading a SKU.
  Widget _buildIdentity() {
    return WDiv(
      className: 'flex flex-col gap-3 p-4 rounded-lg bg-surface-container',
      children: [
        WDiv(
          className: 'flex flex-row items-start gap-3',
          children: [
            WDiv(
              className: '''
                size-20 rounded-md bg-surface-container-high
                flex items-center justify-center
              ''',
              child: const WIcon(_imagePlaceholderIcon, className: 'size-8 text-fg-disabled'),
            ),
            WDiv(
              className: 'flex flex-col gap-2 flex-1 min-w-0',
              children: [
                WDiv(
                  className: 'flex flex-row wrap items-center gap-1',
                  children: [
                    if (_product.categoryLabel != null)
                      Tag(
                        label: _product.categoryLabel!,
                        intent: TagIntent.primary,
                        size: TagSize.sm,
                      ),
                    for (final String tag in _product.tags) Tag(label: tag, size: TagSize.sm),
                  ],
                ),
                if (_product.description != null)
                  WText(_product.description!, className: 'text-sm text-fg-muted'),
                // The tenant's own identifier, mono because it is a code the user
                // compares character by character against a shelf label or an order.
                // It sits here rather than in the page subtitle: the subtitle is the
                // brand, and an earlier pass lost the SKU entirely by merging them.
                if (_product.sku != null)
                  WText('SKU · ${_product.sku}', className: 'font-mono text-xs text-fg-muted'),
              ],
            ),
          ],
        ),
      ],
    );
  }

  /// Barcodes, in mono, with the scan and print affordances beside them.
  ///
  /// Its own section rather than a line in the identity block, because the barcode
  /// is how this product gets scanned, matched against the catalog and labelled. A
  /// product can carry several: a manufacturer EAN plus an internal code we
  /// generated for an item that shipped without one.
  ///
  /// Mono because a barcode is a string of digits a user reads character by
  /// character when comparing it against a physical label.
  ///
  /// The action is "Ekle", not a scan icon. An earlier version put a scan control
  /// here, which was wrong on two counts: the glyph rendered badly, and more
  /// importantly scanning makes no sense on a screen you reached by already
  /// identifying the product. Scanning belongs to the list and capture flows. What
  /// you actually do from here is link another code to this product, for an item
  /// that shipped without one or carries a second manufacturer code.
  ///
  /// Not every card gets an action. A card earns one only when there is something
  /// you would genuinely start from it: "Partiler" does not, because a lot is created
  /// by the stock-in button below, and "Konumlar" does not, because moving stock is
  /// already in the header. Adding an action to each card for symmetry would be
  /// noise competing with the two that mean something.
  /// The fields a user changes, each opening the same sheet.
  ///
  /// ### This is what replaced a `Düzenle` menu entry
  ///
  /// The menu offered `Düzenle` and it went nowhere, because the only form in the app creates a
  /// product rather than editing one. Anılcan's call was field by field: every row here opens
  /// `FieldEditorSheet`, which is the pattern `ai-enrichment.md` already describes and the draft
  /// screen already uses.
  ///
  /// What that buys is one interaction instead of two. A whole-record form has to carry save,
  /// cancel and a dirty state, and it would mean editing works one way on a draft and another way
  /// on a saved product, with the user left to learn which lives where. Changing a brand costs one
  /// tap and one sheet either way.
  ///
  /// `DraftField` rather than a new row type: a tappable label-and-value that opens a sheet is
  /// exactly what it is, and its provenance marks simply go unused on a saved product.
  Widget _buildDetails(BuildContext context) {
    return SectionCard(
      label: Lang.get('screens.product.details_group'),
      children: [
        DraftField(
          label: Lang.get('screens.product_form.name'),
          value: _product.name,
          onTap: () => FieldEditorSheet.show(
            context,
            label: Lang.get('screens.product_form.name'),
            value: _product.name,
          ),
        ),
        DraftField(
          label: Lang.get('screens.product_form.brand'),
          value: _product.brand,
          onTap: () => FieldEditorSheet.show(
            context,
            label: Lang.get('screens.product_form.brand'),
            value: _product.brand,
          ),
        ),
        DraftField(
          label: Lang.get('screens.product_form.sku'),
          value: _product.sku,
          onTap: () => FieldEditorSheet.show(
            context,
            label: Lang.get('screens.product_form.sku'),
            value: _product.sku,
          ),
        ),
        DraftField(
          label: Lang.get('screens.product_form.category'),
          value: _product.categoryLabel,
          onTap: () => FieldEditorSheet.show(
            context,
            label: Lang.get('screens.product_form.category'),
            value: _product.categoryLabel,
          ),
        ),
      ],
    );
  }

  Widget _buildBarcodes() {
    return SectionCard(
      label: Lang.get('screens.product.barcodes_group'),
      count: Lang.get('screens.product.barcode_count', {'count': _product.barcodes.length}),
      children: [
        for (final (String code, String meta) in _product.barcodes) _buildBarcodeRow(code, meta),
      ],
    );
  }

  /// Deliberately NOT routed through [Quantity], despite both being mono runs.
  ///
  /// A barcode has no amount and no unit, so passing it through would mean lying
  /// about `amount:`, and `Quantity` derives its muted-zero treatment from exactly
  /// that field: `amount: 0` silently greys the code out. The review suggested the
  /// reuse and `quantity.preview.dart` appeared to demonstrate it, but that demo was
  /// wrong too and has been removed. A code and a quantity share a typeface and
  /// nothing else.
  Widget _buildBarcodeRow(String code, String meta) {
    return WDiv(
      className: 'flex flex-row items-center justify-between gap-3 py-2',
      children: [
        WDiv(
          className: 'flex flex-col gap-0.5 flex-1 min-w-0',
          children: [
            WText(code, className: 'font-mono text-sm text-fg truncate'),
            WText(meta, className: 'text-xs text-fg-muted truncate'),
          ],
        ),
      ],
    );
  }

  /// The headline figure, with the earliest expiry across every lot beside it.
  ///
  /// The expiry sits here rather than only in the lot list because it changes what
  /// the user does next: five in stock with one already expired is a different
  /// situation from five all fresh, and making them look identical at the top of the
  /// screen would bury it.
  Widget _buildStockSummary() {
    if (widget.isNew) {
      return WDiv(
        className: 'flex flex-col gap-1 p-4 rounded-lg bg-surface-container',
        children: [
          WText(Lang.get('screens.product.total_stock'), className: 'text-xs text-fg-muted'),
          const Quantity(amount: 0, formatted: '0', unit: 'adet', size: QuantitySize.lg),
        ],
      );
    }

    return WDiv(
      className: '''
        flex flex-row items-end justify-between gap-3
        p-4 rounded-lg bg-surface-container
      ''',
      children: [
        WDiv(
          className: 'flex flex-col gap-1',
          children: [
            WText(Lang.get('screens.product.total_stock'), className: 'text-xs text-fg-muted'),
            // Derived, so it cannot disagree with the list row for this product.
            Quantity(
              amount: _product.amount,
              formatted: _product.primaryFigure.$1,
              unit: _product.primaryFigure.$2,
              remainderFormatted: _product.remainderFigure?.$1,
              remainderUnit: _product.remainderFigure?.$2,
              size: QuantitySize.lg,
            ),
          ],
        ),
        WDiv(
          className: 'flex flex-col items-end gap-1',
          children: [
            WText(Lang.get('screens.product.soonest_date'), className: 'text-xs text-fg-muted'),
            // The open unit's clock, which is sooner than any printed date here. A
            // headline showing the printed date while an opened carton expires in two
            // days would be the screen contradicting its own lot list.
            ?ExpiryBadge.maybe(
              label: _product.expiryLabel,
              daysUntilExpiry: _product.daysUntilExpiry,
            ),
          ],
        ),
      ],
    );
  }

  /// Consumption context, which at this data volume is deliberately not a forecast.
  ///
  /// The product has nine movements, under the threshold where SBA is trustworthy,
  /// so the screen shows the user's own target level and says plainly that the
  /// history is not there yet. Showing a confident number from nine points is how a
  /// prediction feature loses its credibility on the first wrong guess.
  ///
  /// **Waste is a count, not the percentage `forecasting.md` names.** The percentage
  /// is the right long-run metric, but one waste event out of three outflows is 33%
  /// and means nothing, and quoting it would break the same honesty rule that keeps
  /// the forecast card empty. A count is a fact rather than an estimate. The card
  /// switches to a percentage once there is enough outflow to divide by.
  ///
  /// Days of cover is deliberately absent. `forecasting.md` says to show it "where it
  /// is known", and it is not known here: it needs a consumption rate, which is the
  /// very thing the middle card says it does not have yet. A third card reading
  /// "Henüz yok" would be noise agreeing with the second one.
  Widget _buildForecast() {
    if (widget.isNew) {
      return WDiv(
        className: 'grid grid-cols-2 md:grid-cols-3 gap-3 items-stretch',
        children: [
          WDiv(
            child: StatCard(
              label: Lang.get('screens.product.stat_target'),
              value: Lang.get('screens.product.stat_target_unset'),
              delta: Lang.get('screens.product.stat_target_unset'),
            ),
          ),
          WDiv(
            child: StatCard(
              label: Lang.get('screens.product.stat_forecast'),
              value: Lang.get('screens.product.stat_forecast_none'),
              delta: Lang.get('screens.product.stat_forecast_progress', {'count': 0, 'needed': 10}),
            ),
          ),
          WDiv(
            child: StatCard(
              label: Lang.get('screens.product.stat_waste'),
              value: '0',
              delta: Lang.get('screens.product.stat_waste_window'),
            ),
          ),
        ],
      );
    }

    return WDiv(
      className: 'grid grid-cols-2 md:grid-cols-3 gap-3 items-stretch',
      children: [
        WDiv(
          child: StatCard(
            label: Lang.get('screens.product.stat_target'),
            value: Lang.get('screens.product.stat_target_value', {'par': _product.parLevel, 'unit': _product.unit}),
            delta: Lang.get('screens.product.stat_target_manual'),
          ),
        ),
        WDiv(
          child: StatCard(
            label: Lang.get('screens.product.stat_forecast'),
            value: Lang.get('screens.product.stat_forecast_none'),
            // The product's real movement count, against the ten `forecasting.md` gates a rate
            // on. It was a hardcoded 9 from when this screen ran on one fixture, which read as a
            // fact and was wrong for every product that was not that fixture.
            delta: Lang.get('screens.product.stat_forecast_progress', {
              'count': _product.movementCount,
              'needed': 10,
            }),
          ),
        ),
        WDiv(
          child: StatCard(
            label: Lang.get('screens.product.stat_waste'),
            // Not invented. A 30-day waste total is an aggregate over movements with the waste
            // reason, and no endpoint sends it yet; a number here would be the screen making one
            // up, which is exactly what the fixture-era `1 adet` was doing.
            value: Lang.get('screens.product.stat_waste_unknown'),
            delta: Lang.get('screens.product.stat_waste_window'),
          ),
        ),
      ],
    );
  }

  Widget _buildLocations() {
    if (widget.isNew) {
      return SectionCard(
        label: Lang.get('screens.product.locations_group'),
        children: [
          WDiv(
            // Full width so MSEmptyState's own `items-center` has something to centre
            // in; see the note in ProductIndexView for why a `justify-center` row is
            // the wrong tool here.
            className: 'w-full',
            child: MSEmptyState(
              icon: _moveIcon,
              title: Lang.get('screens.product.locations_empty'),
              description: Lang.get('screens.product.locations_empty_note'),
            ),
          ),
        ],
      );
    }

    // Derived from the same lots, so the location split necessarily sums to the
    // headline. It did not before: the fridge showed "1 adet" while holding a sealed
    // carton and an open half-litre, so the breakdown came to less than the total it
    // breaks down.
    return SectionCard(
      label: Lang.get('screens.product.locations_group'),
      count: Lang.get('screens.product.locations_count', {'count': _locationIds.length}),
      children: [for (final String locationId in _locationIds) _locationRow(locationId)],
    );
  }

  /// The locations holding live stock, in the order the location list declares them.
  ///
  /// Goes through [ProductListItem.amountAt] rather than counting lots directly, so it
  /// works for both unit models. Counting lots left the serial-tracked screen showing
  /// "0 konum" beside two drills sitting on a shelf, which is the second time a
  /// lot-shaped assumption has quietly broken the other widget.mode.
  List<String> get _locationIds =>
      // Asked of the PRODUCT rather than scanned out of a global option list. With real data the
      // fixture ids match nothing, so scanning `locationOptions` found no locations at all and the
      // screen showed none; the product already knows where its own stock is.
      _product.locationIds.where((id) => _product.amountAt(id) > 0).toList();

  /// One location's row, with its figures taken from the lots it holds.
  ///
  /// The row reports the open remainder separately for the same reason the headline
  /// does, and its badge reports the EARLIEST binding date among its own lots, which
  /// is how the fridge ends up flagged and the pantry does not.
  Widget _locationRow(String locationId) {
    if (_product.tracking == TrackingMode.serial) return _serialLocationRow(locationId);

    final List<LotFixture> lots = _product.lotsAt(locationId);
    final LotFixture? open = lots.where((l) => l.isOpen).firstOrNull;
    final num whole = lots.where((l) => !l.isOpen).fold<num>(0, (a, l) => a + l.remaining);

    final LotFixture soonest = lots.reduce(
      (a, b) => (a.daysUntilExpiry ?? 9999) <= (b.daysUntilExpiry ?? 9999) ? a : b,
    );

    return LocationStockRow(
      path: _locationPath(locationId),
      amount: _product.amountAt(locationId),
      quantity: whole == whole.roundToDouble() ? whole.round().toString() : whole.toString(),
      unit: _product.unit,
      remainderFormatted: open?.formatted,
      remainderUnit: open?.unit,
      lotsLabel: Lang.get('screens.product.lot_count', {'count': lots.length}),
      expiryLabel: soonest.isOpen
          ? Lang.get('screens.product.open_soonest', {'label': soonest.expiryLabel})
          : soonest.expiryLabel,
      daysUntilExpiry: soonest.daysUntilExpiry,
    );
  }

  Widget _buildLots() {
    if (widget.isNew) {
      return SectionCard(
        label: Lang.get('screens.product.lots_group'),
        children: [
          WDiv(
            // Full width so MSEmptyState's own `items-center` has something to centre
            // in; see the note in ProductIndexView for why a `justify-center` row is
            // the wrong tool here.
            className: 'w-full',
            child: MSEmptyState(
              icon: _emptyLotsIcon,
              title: Lang.get('screens.product.lots_empty'),
              description:
                  Lang.get('screens.product.lots_empty_note'),
            ),
          ),
        ],
      );
    }

    // Serial-tracked products get a different section entirely, not a variant of this
    // one. The subject changes: a lot row's subject is a quantity that can be partly
    // consumed, a serial row's is a specific object that is either here or not. Trying
    // to express both in one row means a column that is sometimes "500 ml" and
    // sometimes an IMEI.
    if (_product.tracking == TrackingMode.serial) return _buildSerials();

    // Rendered from the product's own lots, so the count, the sum and the dates
    // cannot disagree with the list row or with each other. A test asserts the live
    // lots add up to `amount`, which is what the hand-written version could not do.
    return SectionCard(
      label: Lang.get('screens.product.lots_group'),
      count: Lang.get('screens.product.lot_count', {'count': _product.lots.length}),
      children: [
        for (final LotFixture lot in _product.lots)
          LotRow(
            remainingAmount: lot.remaining,
            remaining: lot.formatted,
            unit: lot.unit,
            isOpen: lot.isOpen,
            expiryLabel: lot.expiryLabel,
            daysUntilExpiry: lot.daysUntilExpiry,
            openedLabel: lot.openedLabel,
            receivedLabel: lot.receivedLabel,
            lotCode: lot.lotCode,
            isDepleted: lot.isDepleted,
          ),
      ],
    );
  }

  /// A location's row for a serial-tracked product.
  ///
  /// A whole count and no remainder, because there is no fraction to express. The date
  /// is the soonest WARRANTY among the units here, which is what makes a shelf worth
  /// looking at: a shop that misses a warranty expiry eats the repair.
  Widget _serialLocationRow(String locationId) {
    final List<SerialFixture> units = _product.serialsAt(locationId);

    final SerialFixture soonest = units.reduce(
      (a, b) => (a.warrantyDaysRemaining ?? 9999) <= (b.warrantyDaysRemaining ?? 9999) ? a : b,
    );

    return LocationStockRow(
      path: _locationPath(locationId),
      amount: units.length,
      quantity: '${units.length}',
      unit: _product.unit,
      lotsLabel: '${units.length} seri',
      expiryLabel: soonest.warrantyLabel,
      daysUntilExpiry: soonest.warrantyDaysRemaining,
    );
  }

  /// The individually identified units, for a serial-tracked product.
  ///
  /// Collapsible, unlike the lot list. A shop holding forty identical drills has forty
  /// rows here and reads them only when hunting one specific unit, whereas a lot list
  /// is short by nature and is what the user came for. It still starts open, because a
  /// section a new user never sees might as well not exist.
  ///
  /// Units that have left stay in the list, faded. They are the evidence behind the
  /// history, and a shop asked "did we ever have this serial" needs the answer to be
  /// yes rather than silence.
  Widget _buildSerials() {
    final int live = _product.liveSerials.length;

    return SectionCard(
      label: Lang.get('screens.product.serials_group'),
      count: Lang.get('screens.product.serial_count', {'count': live}),
      collapsible: true,
      children: [
        for (final SerialFixture unit in _product.serials)
          SerialRow(
            serial: unit.serial,
            warrantyLabel: unit.warrantyLabel,
            warrantyDaysRemaining: unit.warrantyDaysRemaining,
            receivedLabel: unit.receivedLabel,
            isGone: unit.isGone,
            onTap: () {},
          ),
      ],
    );
  }

  Widget _buildMovements() {
    if (widget.isNew) {
      return SectionCard(
        label: Lang.get('screens.product.activity_group'),
        children: [
          WDiv(
            // Full width so MSEmptyState's own `items-center` has something to centre
            // in; see the note in ProductIndexView for why a `justify-center` row is
            // the wrong tool here.
            className: 'w-full',
            child: MSEmptyState(
              icon: _emptyMovementsIcon,
              title: Lang.get('screens.product.activity_empty'),
              description:
                  Lang.get('screens.product.activity_empty_note'),
            ),
          ),
        ],
      );
    }

    return SectionCard(
      label: Lang.get('screens.product.activity_group'),
      count: Lang.get('screens.product.activity_count', {'count': 9}),
      // Collapsible, unlike the sections above it. This is the audit trail: a user
      // reads it when a number looks wrong, not on every visit, and it is the one
      // section that keeps growing. It still starts open, because a section a new
      // user never sees might as well not exist.
      collapsible: true,
      action: MSButton(
        onPressed: () {},
        intent: ButtonIntent.ghost,
        size: ButtonSize.sm,
        // `axis-min`, not `justify-center`. MSButton's inner row is a Flutter Row,
        // which defaults to MainAxisSize.max, so a button handed free space fills
        // it: this one grew to half the card width and read as a filled panel
        // rather than a link. `justify-center` only centres the content inside
        // that stretched box; `axis-min` is what stops the stretching.
        className: 'py-3.5 axis-min',
        child: WDiv(
          className: 'flex flex-row items-center gap-0.5 axis-min',
          children: [
            WText(Lang.get('screens.product.activity_all')),
            WIcon(_chevronIcon, className: 'size-4'),
          ],
        ),
      ),
      children: [
        const MovementRow(
          // demo-data-start: the movement rows, standing in for ledger entries
          reason: 'Satın alındı',
          // demo-data-end
          deltaAmount: 2,
          delta: '+2',
          unit: 'adet',
          // demo-data-start: the movement rows, standing in for ledger entries
          meta: 'Fiş taraması · 5 Ağu 18:22',
          // demo-data-end
          direction: MovementDirection.inbound,
        ),
        const MovementRow(
          // demo-data-start: the movement rows, standing in for ledger entries
          reason: 'Tüketildi',
          // demo-data-end
          deltaAmount: -1,
          delta: '-1',
          unit: 'adet',
          // demo-data-start: the movement rows, standing in for ledger entries
          meta: 'Anılcan · bugün 09:14',
          // demo-data-end
          direction: MovementDirection.outbound,
        ),
        const MovementRow(
          reason: 'Zayi: bozuldu',
          deltaAmount: -1,
          delta: '-1',
          unit: 'adet',
          // demo-data-start: the movement rows, standing in for ledger entries
          meta: 'Anılcan · bugün 09:15',
          // demo-data-end
          direction: MovementDirection.waste,
        ),
        const MovementRow(
          // demo-data-start: the movement rows, standing in for ledger entries
          reason: 'Sayım düzeltmesi',
          // demo-data-end
          deltaAmount: 1,
          delta: '+1',
          unit: 'adet',
          // demo-data-start: the movement rows, standing in for ledger entries
          meta: 'Asistan onaylı · dün 21:40',
          // demo-data-end
          direction: MovementDirection.correction,
        ),
      ],
    );
  }

  /// Two actions of equal weight, because stock out and stock in are equally
  /// frequent and neither is secondary to the other.
  ///
  /// A single "Hareket ekle" button was the earlier shape, and it was wrong: taking
  /// one carton of milk out is something a cafe does several times a day, and hiding
  /// the direction behind a shared button charged an extra tap to the most frequent
  /// action on the screen. These two read as a matched pair, the way a plus and a
  /// minus do, rather than as two primaries competing for attention.
  ///
  /// Editing and archiving are rare, so they live in the header's overflow instead of
  /// taking width here.
  ///
  /// `justify-center` is load-bearing on both: `fullWidth` and `flex-1` stretch the
  /// button, but the button recipe's base carries `items-center` and says nothing
  /// about the main axis, so a stretched button otherwise leaves its label against
  /// the left edge.
  Widget _buildPrimaryAction(BuildContext context) {
    // **Two filled blue buttons that do opposite things.** That is how this shipped, and it broke
    // DESIGN.md's one-primary-per-view rule in the way that rule exists to prevent: `Stok çıkar`
    // and `Stok ekle` were pixel-identical apart from their label and their glyph, sat next to each
    // other, and removed or added stock. Adding is the affirmative action and keeps the fill;
    // taking out is a peer rather than a footnote, so it gets the bordered treatment instead of
    // `ghost`, which paints no boundary at all.
    //
    // `flex-col md:flex-row`, because two full-width buttons side by side at 390px leave each about
    // 155px and a label plus a glyph does not fit that without truncating, which DESIGN.md forbids.
    return WDiv(
      className: 'flex flex-col md:flex-row gap-3 pb-2',
      children: [
        WDiv(
          className: 'w-full md:flex-1',
          child: MSButton(
            // Disabled with nothing on hand. A stock-out sheet that opens on an empty
            // product has no lot to preselect and nothing to offer, so it would be a
            // sheet whose only outcome is closing it again.
            onPressed: _product.amount == 0
                ? null
                : _consumeStock,
            intent: ButtonIntent.secondary,
            fullWidth: true,
            className: 'justify-center gap-2 bg-surface-container',
            child: WDiv(
              className: 'flex flex-row items-center gap-2',
              children: [
                WIcon(_outIcon, className: 'size-4'),
                WText(Lang.get('screens.product.stock_out')),
              ],
            ),
          ),
        ),
        WDiv(
          className: 'w-full md:flex-1',
          child: MSButton(
            // Never disabled, unlike its neighbour. Adding stock is valid at any
            // level, including from zero: that is how a depleted product comes back.
            onPressed: _receiveStock,
            fullWidth: true,
            className: 'justify-center gap-2',
            child: WDiv(
              className: 'flex flex-row items-center gap-2',
              children: [
                WIcon(_inIcon, className: 'size-4'),
                WText(Lang.get('screens.product.stock_in')),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
