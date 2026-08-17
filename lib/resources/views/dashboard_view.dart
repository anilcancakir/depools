// `defaultTargetPlatform` for the one platform question this screen asks: a phone photographs a
// receipt with its camera and everything else picks a file. `ImagePicker` and `ImageSource` arrive
// through magic's own barrel, which re-exports them, so naming the package here as well is what the
// analyzer calls an unnecessary import.
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart'
    show ButtonIntent, MSBottomSheet, MSButton, MSEmptyState, MSPageScaffold;

import '../../app/controllers/dashboard_controller.dart';
import '../../app/controllers/receipt_controller.dart';
import '../../app/models/movement_entry.dart';
import '../../app/support/movement_copy.dart';
import '../../app/models/dashboard_summary.dart';
import '../../app/support/plural.dart';
import '../../app/support/unit_label.dart';
import '../../ui/components/list_footer/list_footer.dart';
import '../../ui/components/lot_row/lot_row.dart';
import '../../ui/components/movement_row/movement_row.dart';
import '../../ui/components/option_row/option_row.dart';
import '../../ui/components/product_row/product_row.dart';
import '../../ui/components/section_card/section_card.dart';
import '../../ui/components/setup_step/setup_step.dart';
import '../../ui/components/stat_card/stat_card.dart';
import 'products/expiring_fixtures.dart';
import 'products/product_fixtures.dart';
import 'products/shopping_fixtures.dart';

/// The landing page, and the one screen whose job is a QUESTION rather than a list.
///
/// ### What it replaced, and why that mattered
///
/// This file used to be `magic_starter`'s welcome card: a hero glyph, three tiles linking to the
/// framework's docs, GitHub and CLI, an upgrade nudge for a "Pro plan" this product does not sell,
/// and a "Made with love" footer. It was the FIRST screen a signed-in user saw, in English, on a
/// Turkish inventory app, months after eleven real screens had been designed around it.
///
/// ### It answers "neye bakmam lazım", and every number is derived
///
/// Not one figure here is typed. Each comes from the same fixture the destination screen reads, so
/// the dashboard cannot disagree with the page it links to. `test/dashboard_test.dart` locks that:
/// it asserts the counters equal the collections rather than equalling literals, which is the only
/// version of the test that survives a fixture edit.
///
/// The ordering is `forecasting.md`'s own ranking, and it is a claim about urgency rather than a
/// layout preference: a date that has passed cannot be recovered, a date approaching still can be,
/// something already out of stock is a lost sale today, and something merely low is a decision for
/// this week. Waste leads, and the shopping list comes last because it is the only one of the four
/// that is a document the user works through rather than a fact they need to know.
///
/// ### Three rows, never four, and a footer that says how many were hidden (D62)
///
/// Each card shows at most three rows and then a `ListFooter` naming the true total. A dashboard
/// that renders the whole list is the list screen with extra steps, and one that truncates without
/// saying so teaches the user that the numbers at the top are decoration.
///
/// The cap is three rather than five because the four cards have to coexist above the fold on a
/// laptop; measured at 1400x1000, three rows each puts the last card's header just inside the
/// viewport.
///
/// ### The counters are a grid, not a row (D63)
///
/// `grid grid-cols-2 md:grid-cols-4 items-stretch`, matching the product page's idiom. The
/// assistant screen learned this the hard way in the other direction: three stat cards in a plain
/// row came out three different heights, because their labels wrapped unevenly at phone width. On
/// a grid, `items-stretch` makes a row's cells match its tallest, so the four values sit on one
/// baseline at every width without anything being measured in Dart.
@immutable
class DashboardView extends StatefulWidget {
  /// Whether the tenant has any stock at all.
  ///
  /// **"Caught up" and "not started" are not the same empty screen, and treating them as one was a
  /// defect this screen introduced (D64).** Both produce four zeroes, and the first version showed
  /// the same calm `Bekleyen iş yok` for both. To someone who signed up ten seconds ago that reads
  /// as the app claiming their work is done, which is the least useful thing it could say at the
  /// only moment they are deciding whether to continue.
  final bool hasStock;

  /// Whether the dates source could not be read.
  final bool datesFailed;

  /// A summary supplied by the caller, which is how the preview catalog stays offline.
  ///
  /// Null means "read [DashboardController]", which is what the route does. The previews pass one
  /// built from the fixtures, so previewing this screen never issues a request.
  final DashboardSummary? summary;

  /// Creates the [DashboardView], reading from [DashboardController].
  const DashboardView({super.key, this.summary}) : hasStock = true, datesFailed = false;

  /// Creates the view for a tenant that has not added anything yet.
  const DashboardView.fresh({super.key, this.summary})
    : hasStock = false,
      datesFailed = false;

  /// Creates the view with one section's source unavailable, which is its own reviewable state.
  ///
  /// **This is the state that proves the failure design.** A failure replaces the SECTION and
  /// leaves the rest of the page working, and this screen is where that claim is testable: it
  /// reads from four sources, so a dates request that times out must not take the four counters,
  /// the capture actions and the shortage list with it.
  const DashboardView.sectionFailed({super.key, this.summary})
    : hasStock = true,
      datesFailed = true;

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  static const IconData _iconScan = Icons.qr_code_scanner_outlined;
  static const IconData _iconAssistant = Icons.auto_awesome_outlined;
  static const IconData _iconCount = Icons.checklist_outlined;
  static const IconData _iconReceipt = Icons.receipt_long_outlined;
  static const IconData _iconShelf = Icons.photo_camera_outlined;
  static const IconData _iconCalm = Icons.check_circle_outline;

  /// How many rows a dashboard card shows before it defers to its own screen.
  static const int _rowCap = 3;

  DashboardController? _controller;

  bool get datesFailed => widget.datesFailed;

  @override
  void initState() {
    super.initState();

    if (widget.summary != null) return;

    final DashboardController controller = DashboardController.instance
      ..addListener(_onChanged);

    // The same `onInit` contract every wired screen here needs. Getting it wrong on THIS screen is
    // the worst version: a controller that never initialises reports no stock, and a tenant with
    // forty products is shown the first-run setup steps.
    if (!controller.initialized) {
      controller.onInit();
    } else {
      // **Re-asked on every visit, unlike the other screens.** A user comes back here after doing
      // the thing the dashboard told them to do, and a cached "1 expired" after they have just
      // thrown that carton away is the screen contradicting itself. Quiet, so the drawn copy stays
      // on screen while the answer is in flight.
      controller.load(quiet: true);
    }

    _controller = controller;
  }

  @override
  void dispose() {
    _controller?.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  /// What the screen draws, whatever the source.
  DashboardSummary? get _summary => widget.summary ?? _controller?.summary;

  @override
  Widget build(BuildContext context) {
    final DashboardSummary? summary = _summary;

    // **Nothing until there is an answer, and this screen more than any other.** It has two SHAPES
    // rather than a full and an empty one, so guessing wrong shows a tenant with forty products the
    // setup steps for a brand new account.
    if (summary == null) return const SizedBox.shrink();

    final List<DatedLot> expired = summary.expired;
    final List<DatedLot> approaching = summary.approaching;
    final List<ProductListItem> out = summary.outOfStock;
    final List<ProductListItem> low = summary.belowTarget;
    final int products = summary.products;
    final int locations = summary.locations;
    final bool isCalm = summary.expiredCount == 0 &&
        summary.approachingCount == 0 &&
        summary.outOfStockCount == 0 &&
        summary.belowTargetCount == 0;

    // A fresh tenant gets a different screen, not a thinner one. The counters, the four cards and
    // the movement history all describe stock, and every one of them would render as a zero or an
    // empty state: six ways of saying the same nothing.
    if (!summary.hasStock) return _buildFirstRun(context);

    return MSPageScaffold(
      title: Lang.get('screens.dashboard.title'),
      // The scope of everything below, so a counter reading 6 is legible as six OF something.
      subtitle: Lang.get('screens.dashboard.subtitle', {'products': products, 'locations': locations}),
      children: [
        // **The COUNTERS are the whole set and the lists are the first three.** Passing the list
        // lengths would make every card say "3" however many products are actually short, which is
        // the disagreement between a figure and the page it links to that this screen exists to
        // avoid.
        _buildCounters(
          summary.expiredCount,
          summary.approachingCount,
          summary.outOfStockCount,
          summary.belowTargetCount,
        ),
        _buildCapture(context),
        if (isCalm) _buildCalm(),
        if (expired.isNotEmpty || approaching.isNotEmpty) _buildDates(expired, approaching),
        if (out.isNotEmpty || low.isNotEmpty) _buildStock(out, low),
        if (pendingLines.isNotEmpty) _buildShopping(),
        _buildActivity(summary.activity),
      ],
    );
  }

  /// The first thing a new tenant sees.
  ///
  /// ### Three steps, in the order the data depends on itself
  ///
  /// Locations first, because a product with nowhere to be cannot be counted and cannot appear on
  /// a per-location dates walk. Products second. Targets third, and it is a step rather than a
  /// detail because a product with no target can never appear in `Azalanlar` however low it gets:
  /// the screen would stay empty and look broken. That is the same gap the running-low empty state
  /// names, said before it can bite instead of after.
  ///
  /// ### Each step says what it BUYS
  ///
  /// A first-run screen is where someone decides whether the setup is worth their afternoon, and
  /// they have no model of the product yet. `Konumları tanımlayın` alone is an instruction with no
  /// reason attached.
  ///
  /// ### No capture card here, and dropping it fixed two things
  ///
  /// The first draft reused the populated dashboard's `Ekle` card. It offered `Sayım yap` to a
  /// tenant with zero products, which is an action that cannot succeed: a count of nothing lands on
  /// an empty screen and teaches the user that the buttons are decorative. It also put a second
  /// `bg-primary` on the page beside step 1's marker, which DESIGN.md allows exactly one of.
  ///
  /// The steps already carry the actions, in the order the data depends on itself, so the card was
  /// a second copy of step 2 plus one action that does not work yet.
  Widget _buildFirstRun(BuildContext context) {
    return MSPageScaffold(
      title: Lang.get('screens.dashboard.welcome_title'),
      subtitle: Lang.get('screens.dashboard.welcome_subtitle'),
      children: [
        SectionCard(
          label: Lang.get('screens.dashboard.setup_group'),
          count: Lang.get('screens.dashboard.setup_count', {'count': 3}),
          children: [
            SetupStep(
              marker: '1',
              title: Lang.get('screens.dashboard.step_locations'),
              description: Lang.get('screens.dashboard.step_locations_note'),
              state: SetupStepState.current,
              actionLabel: Lang.get('screens.dashboard.step_locations_action'),
              onAction: () => MagicRoute.to('/locations'),
            ),
            SetupStep(
              marker: '2',
              title: Lang.get('screens.dashboard.step_products'),
              description: Lang.get('screens.dashboard.step_products_note'),
              // **The label names where it goes.** It read "Ürün ekle" and opened the barcode
              // scanner, which promises a product form and delivers a camera; now that
              // `/products/new` exists that promise has somewhere real to point, which made the
              // mismatch worse rather than better.
              //
              // The destination stays the scanner because `inventory-core.md` is explicit that a
              // first-run surface offers the FASTEST capture paths rather than a create button,
              // and the step's own description already opens with "Barkodu okutun". The other two
              // paths it names stay reachable: the assistant floats on every screen and the stock
              // list's empty state offers the receipt and the photo.
              actionLabel: Lang.get('screens.dashboard.step_products_action'),
              onAction: () => MagicRoute.to('/scan'),
            ),
            SetupStep(
              marker: '3',
              title: Lang.get('screens.dashboard.step_targets'),
              // The gap named before it bites. The running-low screen's own empty state says the
              // same thing, but by then the user has already opened a screen expecting rows.
              description: Lang.get('screens.dashboard.step_targets_note'),
              actionLabel: Lang.get('screens.dashboard.step_targets_action'),
              onAction: () => MagicRoute.to('/products'),
            ),
          ],
        ),
      ],
    );
  }

  /// The four figures, each one the length of the collection its card renders.
  ///
  /// The labels carry their own units (`ürün`, `parti`) in the delta line rather than in the value,
  /// because a column of bare numerals reading "1 4 2 6" is unreadable at a glance and a value of
  /// `1 parti` breaks the shared baseline the grid exists to hold.
  Widget _buildCounters(int expired, int approaching, int out, int low) {
    return WDiv(
      className: 'grid grid-cols-2 md:grid-cols-4 gap-3 items-stretch',
      children: [
        WDiv(
          child: StatCard(
            label: Lang.get('screens.dashboard.counter_expired'),
            value: '$expired',
            delta: Lang.get('screens.dashboard.unit_batches'),
          ),
        ),
        WDiv(
          child: StatCard(
            label: Lang.get('screens.dashboard.counter_approaching'),
            value: '$approaching',
            delta: Lang.get('screens.dashboard.counter_within', {'days': defaultHorizonDays}),
          ),
        ),
        WDiv(
          child: StatCard(
            label: Lang.get('screens.dashboard.counter_out'),
            value: '$out',
            delta: Lang.get('screens.dashboard.unit_products'),
          ),
        ),
        WDiv(
          child: StatCard(
            label: Lang.get('screens.dashboard.counter_low'),
            value: '$low',
            delta: Lang.get('screens.dashboard.unit_products'),
          ),
        ),
      ],
    );
  }

  /// The three ways stock gets in or gets counted.
  ///
  /// On the dashboard rather than behind a menu because they are the only actions here: every other
  /// card on this screen is something to READ. `Tara` leads and is the one primary fill on the
  /// page, per DESIGN.md's rule that `bg-primary` belongs to a single action in a view.
  ///
  /// They reflow to a column at narrow widths instead of shrinking, so a 44pt target stays a 44pt
  /// target. `wrap` alone would leave a lone third button on its own line at some widths, which
  /// reads as a mistake rather than as a layout.
  Widget _buildCapture(BuildContext context) {
    return SectionCard(
      label: Lang.get('screens.dashboard.capture_group'),
      children: [
        // **Two rows, split by whether the camera is the instrument.** Five actions on one row
        // is a menu rather than a set of choices, and the honest grouping is the one
        // `product.md` already uses: barcode, receipt and shelf photo are all "point the camera
        // at the thing", while the assistant and a count are not.
        //
        // The receipt and shelf-photo paths were designed and had no way in at all until now,
        // which is what made two of the four orphan screens unreachable.
        WDiv(
          className: 'flex flex-col md:flex-row gap-2 w-full',
          children: [
            _captureButton(context, Lang.get('screens.dashboard.capture_scan'), _iconScan, '/scan', ButtonIntent.primary),
            // The one capture action that is not a navigation. The receipt path starts with the
            // photograph, so the button opens the camera and only then goes to the review screen;
            // sending the user to `/receipt` first would show a list of receipts to somebody who
            // asked to capture one.
            _captureButton(
              context,
              Lang.get('screens.dashboard.capture_receipt'),
              _iconReceipt,
              '/receipt',
              ButtonIntent.secondary,
              _captureReceipt,
            ),
            _captureButton(context, Lang.get('screens.dashboard.capture_shelf'), _iconShelf, '/shelf-photo'),
          ],
        ),
        WDiv(
          className: 'flex flex-col md:flex-row gap-2 w-full',
          children: [
            _captureButton(context, Lang.get('screens.dashboard.capture_assistant'), _iconAssistant, '/assistant'),
            _captureButton(context, Lang.get('screens.dashboard.capture_count'), _iconCount, '/stock-take'),
          ],
        ),
      ],
    );
  }

  /// One capture action.
  ///
  /// Card tone on the two secondary buttons: `secondary` ships `bg-surface-container-high`, which
  /// is DESIGN.md's input fill and reads as a disabled control on a light card.
  ///
  /// [onPressed] overrides the navigation for the one action that has work to do before it can
  /// navigate. It is a parameter rather than a second copy of this button, because the width
  /// arrangement below is the part that has already gone wrong once and must not be duplicated.
  Widget _captureButton(
    BuildContext context,
    String label,
    IconData icon,
    String path, [
    ButtonIntent intent = ButtonIntent.secondary,
    VoidCallback? onPressed,
  ]) {
    return WDiv(
      // **`w-full md:flex-1`, not `flex-1`.** `flex-1` is axis-dependent: in the `md:flex-row`
      // arrangement it divides the WIDTH, but at phone width the parent is `flex-col` and the same
      // token asks for a share of the HEIGHT. The page scrolls vertically, so that height is
      // unbounded, and the whole screen rendered blank behind a stack of
      // `RenderBox was not laid out` / `RenderFractionallySizedOverflowBox` assertions that name
      // neither this widget nor the token. The wide preview cannot show it, because the wide
      // preview never enters the column arrangement.
      className: 'w-full md:flex-1 min-w-0',
      child: MSButton(
        onPressed: onPressed ?? () => MagicRoute.to(path),
        intent: intent,
        fullWidth: true,
        className: intent == ButtonIntent.secondary
            ? 'justify-center gap-2 bg-surface-container'
            : 'justify-center gap-2',
        child: WDiv(
          className: 'flex flex-row items-center gap-2',
          children: [WIcon(icon, className: 'size-5'), WText(label)],
        ),
      ),
    );
  }

  /// Photographs a receipt, uploads it, and goes to the review screen.
  ///
  /// The upload is what creates the receipt, so the work survives from the moment the shutter
  /// closes: nothing is extracted off it in this slice, and the review screen says so rather than
  /// showing an empty document.
  Future<void> _captureReceipt() async {
    final XFile? picked = await _pickReceipt();

    // A dismissed picker is an answer rather than a failure, and says nothing.
    if (picked == null) return;

    final ReceiptUploadOutcome outcome = await ReceiptController.instance.upload(picked);

    if (!mounted) return;

    if (outcome.succeeded) {
      MagicRoute.to('/receipt');

      return;
    }

    // A duplicate is an answer too: the same photograph reaching the server twice is the double
    // tap, the retry and the offline replay, so it is offered rather than refused.
    if (!outcome.isDuplicate) {
      MagicFeedback.error(
        Lang.get('screens.dashboard.capture_receipt'),
        outcome.message ?? Lang.get('screens.receipt.upload_failed'),
      );

      return;
    }

    await _offerExistingReceipt();
  }

  /// The picker, and the one place this screen asks what kind of device it is on.
  ///
  /// A phone gets the camera, because photographing the paper in your hand is the whole point.
  /// Every other platform gets its file dialog, which is what `image_picker` falls back to there
  /// anyway. `DESIGN.md` allows exactly this: the feature is present on all three platforms and only
  /// the instrument differs.
  Future<XFile?> _pickReceipt() {
    final ImagePicker picker = ImagePicker();
    final bool handheld = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);

    return picker.pickImage(
      source: handheld ? ImageSource.camera : ImageSource.gallery,
      // Capped on the way IN, so a 12 megapixel photograph is not carried over a phone connection to
      // be refused by the server's own limit. The server re-encodes what it stores, so nothing
      // downstream depends on the original resolution.
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 85,
    );
  }

  /// The receipt the tenant already has, and a way into it.
  ///
  /// The server answers 409 with that receipt rather than refusing outright, so the honest offer is
  /// to open it. `/receipt` is the only path there is in this slice, so it lands on the LIST holding
  /// that receipt rather than on the receipt itself; `/receipt/:id` is slice 2's, where a receipt
  /// finally has lines worth linking straight to.
  Future<void> _offerExistingReceipt() async {
    final String? action = await MSBottomSheet.show<String>(
      context,
      title: Lang.get('screens.receipt.duplicate'),
      // No description: a 409 body is `{'data': ...}` and carries no sentence, so the outcome's
      // message is always this same key and the sheet would print it twice. This used to compare the
      // two and pass the message when they differed, which read as a defence against a server that
      // forgot to explain itself and was in fact a branch that could never be taken.
      description: null,
      body: Builder(
        // A `Builder`, so the pop happens on the SHEET's context and not this screen's.
        // `Navigator.of` from here resolves the navigator the PAGE is on, and with the shell's
        // nested navigator in play that pop takes the page rather than the sheet.
        builder: (BuildContext sheetContext) => OptionRow(
          label: Lang.get('screens.receipt.duplicate_open'),
          semanticLabel: Lang.get('screens.receipt.duplicate_open'),
          onTap: () => Navigator.of(sheetContext).pop('open'),
        ),
      ),
    );

    if (action == null || !mounted) return;

    // The LIST, which is the only receipt route this slice has, and the label says so rather than
    // promising to open the one receipt: `screens.receipt.duplicate_open` reads "Go to receipts".
    // It said "Open the receipt" and could not, which is a promise the screen has no way to keep
    // until `/receipt/:id` lands in slice 2. The receipt is in that list; the user finds it there.
    MagicRoute.to('/receipt');
  }

  /// What is running out of time, expired first.
  ///
  /// Rendered with the same `LotRow` the dates screen uses, so a row here and the row it links to
  /// are the same widget rather than two things that have to be kept looking alike.
  Widget _buildDates(List<DatedLot> expired, List<DatedLot> approaching) {
    final List<DatedLot> rows = <DatedLot>[...expired, ...approaching];

    return SectionCard(
      label: Lang.get('screens.dashboard.dates_group'),
      // The count and the "see all" action go with the data: a header claiming five batches above
      // a card that could not read them is the header-contradicts-its-list defect again.
      count: datesFailed
          ? null
          : plural(
              'screens.dashboard.count_batches',
              _summary?.expiredCount ?? 0 + (_summary?.approachingCount ?? 0),
              {'count': (_summary?.expiredCount ?? 0) + (_summary?.approachingCount ?? 0)},
            ),
      action: datesFailed ? null : _seeAll('/dates', Lang.get('screens.dashboard.dates_action')),
      error: datesFailed ? Lang.get('screens.dashboard.dates_failed') : null,
      onRetry: datesFailed ? () {} : null,
      children: [
        for (final DatedLot row in rows.take(_rowCap))
          LotRow(
            productName: row.productName,
            remainingAmount: row.remaining,
            remaining: row.formatted,
            unit: row.unit,
            expiryLabel: row.label,
            daysUntilExpiry: row.daysUntilExpiry,
            receivedLabel: row.receivedLabel,
            lotCode: row.lotCode,
            isOpen: row.isOpen,
            openedLabel: row.receivedLabel,
          ),
        _hiddenCount(
          (_summary?.expiredCount ?? 0) + (_summary?.approachingCount ?? 0),
          rows.take(_rowCap).length,
          Lang.get('screens.dashboard.unit_batches'),
        ),
      ],
    );
  }

  /// What is short, gone-entirely first.
  Widget _buildStock(List<ProductListItem> out, List<ProductListItem> low) {
    // `belowTarget` already contains the out-of-stock rows, so they are pulled to the front
    // rather than concatenated: appending `out` would list the same product twice, which is the
    // exact disagreement between a list and its summary this screen is supposed to prevent.
    final List<ProductListItem> rows = <ProductListItem>[
      ...out,
      ...low.where((ProductListItem p) => !p.isOut),
    ];

    return SectionCard(
      label: Lang.get('screens.dashboard.stock_group'),
      count: plural(
        'screens.dashboard.count_products',
        _shortTotal,
        {'count': _shortTotal},
      ),
      action: _seeAll('/running-low', Lang.get('screens.dashboard.stock_action')),
      children: [
        for (final ProductListItem p in rows.take(_rowCap)) _productRow(p),
        _hiddenCount(_shortTotal, rows.take(_rowCap).length, Lang.get('screens.dashboard.unit_products')),
      ],
    );
  }

  /// How many products are short in total, which is what the card's count says.
  ///
  /// The two sets do not overlap: `below_par` requires stock above zero, so a product holding
  /// nothing is out of stock and NOT below target. Adding them is therefore a count rather than a
  /// double count, and the endpoint's own test pins that.
  int get _shortTotal =>
      (_summary?.outOfStockCount ?? 0) + (_summary?.belowTargetCount ?? 0);

  /// One short product, rendered by the list screen's own row.
  Widget _productRow(ProductListItem product) {
    final (String primary, String? primaryUnit) = product.primaryFigure;
    final (String, String?)? remainder = product.remainderFigure;

    // **A product with no target is still out of stock**, and the endpoint answers that set without
    // requiring one. The fixture always carried a target, so this line had never been handed a null
    // and rendered "Target null piece" the first time real rows arrived.
    final num? par = product.parLevel;

    return ProductRow(
      name: product.name,
      meta: par == null
          ? Lang.get('screens.dashboard.stock_no_target')
          : Lang.get('screens.dashboard.stock_meta', {
              'par': par,
              'unit': unitLabel(product.unit, par),
            }),
      amount: product.amount,
      formatted: primary,
      unit: primaryUnit,
      remainderFormatted: remainder?.$1,
      remainderUnit: remainder?.$2,
      parLevel: product.parLevel,
      onTap: () => MagicRoute.to('/running-low'),
    );
  }

  /// What to buy, as a count and a way in.
  ///
  /// Deliberately NOT three shopping rows. The list is a document the user works through with a
  /// phone in one hand, and a partial copy of it invites ticking items off in the wrong place;
  /// the other three cards are facts, which a partial view of is still useful.
  Widget _buildShopping() {
    return SectionCard(
      label: Lang.get('screens.dashboard.shopping_group'),
      count: Lang.get('screens.dashboard.shopping_count', {'count': pendingLines.length}),
      action: _seeAll('/shopping', Lang.get('screens.dashboard.shopping_action')),
      children: [
        WText(
          Lang.get('screens.dashboard.shopping_note'),
          className: 'text-sm text-fg-muted',
        ),
      ],
    );
  }

  /// What the app did last, so an automatic write is never a surprise.
  ///
  /// **The tenant's whole ledger, not one product's.** That is the difference from the product
  /// screen's own card, and it is why the row leads with the PRODUCT here: on a feed that spans
  /// products, "Purchase" alone says something moved without saying what.
  Widget _buildActivity(List<MovementEntry> rows) {
    return SectionCard(
      label: Lang.get('screens.dashboard.activity_group'),
      count: plural('screens.dashboard.count_changes', rows.length, {'count': rows.length}),
      collapsible: true,
      children: [
        for (final MovementEntry entry in rows.take(_rowCap)) _activityRow(entry),
        // The activity feed is the one card whose total IS what it was sent: the endpoint answers the
        // last few and there is no separate figure for "every movement ever", which is not a number
        // anybody wants on a dashboard.
        _hiddenCount(rows.length, rows.take(_rowCap).length, Lang.get('screens.dashboard.unit_changes')),
      ],
    );
  }

  /// One ledger entry, composed the same way the product screen composes its own.
  ///
  /// The two differ in exactly one place, and it is the one the feed's scope decides: the headline
  /// is the product name where the payload carries one, with the reason falling to the meta line
  /// beside the place and the time. A product's own card does the reverse, because the name is
  /// already in its header.
  Widget _activityRow(MovementEntry entry) {
    // `.abs()` on both, because the sign is the delta's job: a negative entered figure would render
    // `+-1` and pluralise on a negative number.
    final double amount = (entry.enteredQuantity ?? entry.delta).abs();
    final String? unit = entry.enteredUnit;
    final String reason = movementReasonLabel(entry.reason);

    final List<String> meta = <String>[
      reason,
      ?movementActorLabel(entry.actorType, entry.actorName),
      ?entry.locationName,
      ?ProductListItem.formatDate(entry.at?.toLocal().toIso8601String()),
    ];

    return MovementRow(
      reason: entry.productName ?? reason,
      deltaAmount: entry.delta,
      delta: '${entry.delta < 0 ? '-' : '+'}${ProductListItem.format(amount)}',
      unit: unit == null ? null : unitLabelFor(unit, ProductListItem.format(amount)),
      // The reason is dropped from the meta when it is already the headline, which happens only for
      // a row whose product the payload could not name.
      meta: (entry.productName == null ? meta.skip(1) : meta).join(' · '),
      direction: movementDirection(entry.reason, entry.delta),
    );
  }

  /// Nothing needs attention, which is the outcome the product is for.
  ///
  /// A dashboard with four zeroes and no cards under them looks broken rather than calm, so the
  /// good state says so in words. It is reachable: every counter here is derived, so a tenant who
  /// has cleared their dates and restocked lands on exactly this.
  Widget _buildCalm() {
    return SectionCard(
      label: Lang.get('screens.dashboard.calm_group'),
      children: [
        WDiv(
          className: 'w-full',
          child: MSEmptyState(
            icon: _iconCalm,
            title: Lang.get('screens.dashboard.calm_title'),
            description:
                Lang.get('screens.dashboard.calm_description'),
          ),
        ),
      ],
    );
  }

  /// The link into the full screen, in the card's own header.
  Widget _seeAll(String path, String label) {
    return MSButton(
      onPressed: () => MagicRoute.to(path),
      intent: ButtonIntent.ghost,
      className: 'px-2 py-2',
      semanticLabel: label,
      child: WText(label, className: 'text-sm'),
    );
  }

  /// How many rows the cap hid, or nothing when it hid none.
  ///
  /// `ListFooter` rather than a bare sentence, so the "and N more" line is the same component the
  /// paginated lists use and reads identically wherever a list stops short.
  ///
  /// **The label states what is HIDDEN, not what is shown, and that is a width fix as well as a
  /// better sentence.** The first version read `5 parti içinden ilk 3 gösteriliyor` and overflowed
  /// its row by 25 logical pixels in the 390px frame; the azalanlar card's copy of it overflowed by
  /// 11. Two rendered footers, two overflows, and the third card starts collapsed so it never laid
  /// out. `+2 parti` also answers the question the reader actually has, which is how much they are
  /// not seeing.
  ///
  /// Worth knowing for the next hunt: this only reports on the FIRST paint after a restart, because
  /// Flutter announces an overflow once per `RenderFlex` instance. Re-navigating to the screen
  /// showed a clean buffer and made it look fixed when it was not.
  /// How many the card is not showing.
  ///
  /// **[total] is the whole set and [shown] is what the payload actually sent**, and they are two
  /// different numbers now that the server caps its preview. The first version passed the preview
  /// length as the total, so a card headed "5 batches" showed three rows and said "+1 more": the
  /// header and the footer disagreed by exactly what the endpoint had trimmed.
  Widget _hiddenCount(int total, int shown, String noun) {
    final int hidden = total - shown;

    if (hidden <= 0) return const SizedBox.shrink();

    return ListFooter(
      state: ListFooterState.end,
      pageSize: shown,
      totalLabel: plural(
        'screens.dashboard.hidden_more',
        hidden,
        {'count': hidden, 'noun': noun},
      ),
    );
  }
}
