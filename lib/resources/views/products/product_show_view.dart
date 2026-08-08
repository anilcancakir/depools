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
        MSDropdownMenuItem,
        MSEmptyState;

import '../../../ui/components/expiry_badge/expiry_badge.dart';
import '../../../ui/components/location_stock_row/location_stock_row.dart';
import '../../../ui/components/lot_row/lot_row.dart';
import '../../../ui/components/movement_row/movement_row.dart';
import '../../../ui/components/quantity/quantity.dart';
import '../../../ui/components/section_card/section_card.dart';
import '../../../ui/components/serial_row/serial_row.dart';
import '../../../ui/components/stat_card/stat_card.dart';
import '../../../ui/components/tag/index.dart';
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
class ProductShowView extends StatelessWidget {
  static const IconData _imagePlaceholderIcon = Icons.photo_outlined;
  static const IconData _moveIcon = Icons.swap_horiz_outlined;
  static const IconData _labelIcon = Icons.qr_code_2_outlined;
  static const IconData _moreIcon = Icons.more_horiz_outlined;
  static const IconData _outIcon = Icons.remove_outlined;
  static const IconData _inIcon = Icons.add_outlined;
  static const IconData _chevronIcon = Icons.chevron_right_outlined;
  static const IconData _emptyLotsIcon = Icons.inventory_2_outlined;
  static const IconData _emptyMovementsIcon = Icons.history_outlined;

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

  /// Creates the [ProductShowView].
  const ProductShowView({super.key}) : isNew = false, mode = TrackingMode.lot;

  /// Creates the view for a product that has no stock or history yet.
  const ProductShowView.newProduct({super.key}) : isNew = true, mode = TrackingMode.lot;

  /// Creates the view for a serial-tracked product (D28).
  ///
  /// A separate entry point rather than a parameter on the default one, because the
  /// serial case has to be REVIEWABLE. Half this design only exists on this path, and
  /// a variant reachable only by editing a fixture is a variant nobody looks at.
  const ProductShowView.serialTracked({super.key}) : isNew = false, mode = TrackingMode.serial;

  /// The product this screen renders, read from the SAME fixture the list uses.
  ///
  /// Not a second set of literals. This screen hand-wrote its own numbers and drifted
  /// from the list three ways in one sitting: total 5 against 2.5, target 6 against 4,
  /// and lots summing to 4.5 while holding an expired carton the list did not have. A
  /// user opens the detail screen to check a number they doubt, so it is the last
  /// place that can afford its own opinion.
  ProductListItem get _product => productFixtures.firstWhere((p) => p.tracking == mode);

  @override
  Widget build(BuildContext context) {
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
              : () => StockMoveSheet.show(context, product: _product),
          disabled: _product.amount == 0,
          intent: ButtonIntent.ghost,
          className: 'min-h-11 min-w-11 justify-center',
          semanticLabel: 'Konum değiştir',
          child: const WIcon(_moveIcon),
        ),
        MSButton(
          onPressed: () {},
          intent: ButtonIntent.ghost,
          className: 'min-h-11 min-w-11 justify-center',
          semanticLabel: 'Etiket bas',
          child: const WIcon(_labelIcon),
        ),
        MSDropdownMenu(
          items: [
            MSDropdownMenuItem(label: 'Barkod ekle', onTap: () {}),
            MSDropdownMenuItem(label: 'Ürünü düzenle', onTap: () {}),
            MSDropdownMenuItem(label: 'Arşivle', onTap: () {}),
          ],
          child: MSButton(
            // Null on purpose, and NOT disabled: MSDropdownMenu owns the gesture and
            // this button is only its trigger's appearance. Passing `disabled: true`
            // here would grey out a control that works.
            onPressed: null,
            intent: ButtonIntent.ghost,
            className: 'min-h-11 min-w-11 justify-center',
            semanticLabel: 'Diğer işlemler',
            child: const WIcon(_moreIcon),
          ),
        ),
      ],
      children: [
        _buildIdentity(),
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
  Widget _buildBarcodes() {
    return SectionCard(
      label: 'Barkodlar',
      count: '${_product.barcodes.length} kod',
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
    if (isNew) {
      return WDiv(
        className: 'flex flex-col gap-1 p-4 rounded-lg bg-surface-container',
        children: [
          WText('Toplam stok', className: 'text-xs text-fg-muted'),
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
            WText('Toplam stok', className: 'text-xs text-fg-muted'),
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
            WText('En yakın tarih', className: 'text-xs text-fg-muted'),
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
    if (isNew) {
      return const WDiv(
        className: 'grid grid-cols-2 md:grid-cols-3 gap-3 items-stretch',
        children: [
          WDiv(
            child: StatCard(label: 'Hedef seviye', value: 'Belirlenmedi', delta: 'Belirlenmedi'),
          ),
          WDiv(
            child: StatCard(
              label: 'Tüketim tahmini',
              value: 'Henüz yok',
              delta: '0 hareket, 10 gerekiyor',
            ),
          ),
          WDiv(
            child: StatCard(label: 'Zayi', value: '0', delta: 'son 30 günde'),
          ),
        ],
      );
    }

    return WDiv(
      className: 'grid grid-cols-2 md:grid-cols-3 gap-3 items-stretch',
      children: [
        WDiv(
          child: StatCard(
            label: 'Hedef seviye',
            value: '${_product.parLevel} ${_product.unit}',
            delta: 'Elle belirlendi',
          ),
        ),
        const WDiv(
          child: StatCard(
            label: 'Tüketim tahmini',
            value: 'Henüz yok',
            delta: '9 hareket, 10 gerekiyor',
          ),
        ),
        const WDiv(
          child: StatCard(label: 'Zayi', value: '1 adet', delta: 'son 30 günde'),
        ),
      ],
    );
  }

  Widget _buildLocations() {
    if (isNew) {
      return SectionCard(
        label: 'Konumlar',
        children: [
          WDiv(
            // Full width so MSEmptyState's own `items-center` has something to centre
            // in; see the note in ProductIndexView for why a `justify-center` row is
            // the wrong tool here.
            className: 'w-full',
            child: MSEmptyState(
              icon: _moveIcon,
              title: 'Henüz bir konumda değil',
              description: 'Stok girişinde konum sorulur, sonraki girişlerde otomatik önerilir.',
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
      label: 'Konumlar',
      count: '${_locationIds.length} konum',
      children: [for (final String locationId in _locationIds) _locationRow(locationId)],
    );
  }

  /// The locations holding live stock, in the order the location list declares them.
  ///
  /// Goes through [ProductListItem.amountAt] rather than counting lots directly, so it
  /// works for both unit models. Counting lots left the serial-tracked screen showing
  /// "0 konum" beside two drills sitting on a shelf, which is the second time a
  /// lot-shaped assumption has quietly broken the other mode.
  List<String> get _locationIds =>
      locationOptions.map((o) => o.id).where((id) => _product.amountAt(id) > 0).toList();

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
      path: resolveLocationPath(locationId) ?? locationId,
      amount: _product.amountAt(locationId),
      quantity: whole == whole.roundToDouble() ? whole.round().toString() : whole.toString(),
      unit: _product.unit,
      remainderFormatted: open?.formatted,
      remainderUnit: open?.unit,
      lotsLabel: '${lots.length} parti',
      expiryLabel: soonest.isOpen ? 'Açık · ${soonest.expiryLabel}' : soonest.expiryLabel,
      daysUntilExpiry: soonest.daysUntilExpiry,
    );
  }

  Widget _buildLots() {
    if (isNew) {
      return SectionCard(
        label: 'Partiler',
        children: [
          WDiv(
            // Full width so MSEmptyState's own `items-center` has something to centre
            // in; see the note in ProductIndexView for why a `justify-center` row is
            // the wrong tool here.
            className: 'w-full',
            child: MSEmptyState(
              icon: _emptyLotsIcon,
              title: 'Parti yok',
              description:
                  'Her stok girişi bir parti açar. Son kullanma tarihi girildiğinde '
                  'önce tükenmesi gereken parti buradan izlenir.',
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
      label: 'Partiler',
      count: '${_product.lots.length} parti',
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
      path: resolveLocationPath(locationId) ?? locationId,
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
      label: 'Seri numaraları',
      count: '$live adet',
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
    if (isNew) {
      return SectionCard(
        label: 'Hareketler',
        children: [
          WDiv(
            // Full width so MSEmptyState's own `items-center` has something to centre
            // in; see the note in ProductIndexView for why a `justify-center` row is
            // the wrong tool here.
            className: 'w-full',
            child: MSEmptyState(
              icon: _emptyMovementsIcon,
              title: 'Hiç hareket yok',
              description:
                  'İlk giriş ya da çıkış aşağıdaki iki butonla kaydedilir. '
                  'Tüketim tahmini için gereken geçmiş buradan başlar.',
            ),
          ),
        ],
      );
    }

    return SectionCard(
      label: 'Hareketler',
      count: '9 kayıt',
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
        className: 'min-h-11 axis-min',
        child: const WDiv(
          className: 'flex flex-row items-center gap-0.5 axis-min',
          children: [
            WText('Tümü'),
            WIcon(_chevronIcon, className: 'size-4'),
          ],
        ),
      ),
      children: [
        const MovementRow(
          reason: 'Satın alındı',
          deltaAmount: 2,
          delta: '+2',
          unit: 'adet',
          meta: 'Fiş taraması · 5 Ağu 18:22',
          direction: MovementDirection.inbound,
        ),
        const MovementRow(
          reason: 'Tüketildi',
          deltaAmount: -1,
          delta: '-1',
          unit: 'adet',
          meta: 'Anılcan · bugün 09:14',
          direction: MovementDirection.outbound,
        ),
        const MovementRow(
          reason: 'Zayi: bozuldu',
          deltaAmount: -1,
          delta: '-1',
          unit: 'adet',
          meta: 'Anılcan · bugün 09:15',
          direction: MovementDirection.waste,
        ),
        const MovementRow(
          reason: 'Sayım düzeltmesi',
          deltaAmount: 1,
          delta: '+1',
          unit: 'adet',
          meta: 'Asistan onaylı · dün 21:40',
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
                : () => StockOutSheet.show(context, product: _product),
            intent: ButtonIntent.secondary,
            fullWidth: true,
            className: 'justify-center gap-2 bg-surface-container',
            child: const WDiv(
              className: 'flex flex-row items-center gap-2',
              children: [
                WIcon(_outIcon, className: 'size-4'),
                WText('Stok çıkar'),
              ],
            ),
          ),
        ),
        WDiv(
          className: 'w-full md:flex-1',
          child: MSButton(
            // Never disabled, unlike its neighbour. Adding stock is valid at any
            // level, including from zero: that is how a depleted product comes back.
            onPressed: () => StockInSheet.show(context, product: _product),
            fullWidth: true,
            className: 'justify-center gap-2',
            child: const WDiv(
              className: 'flex flex-row items-center gap-2',
              children: [
                WIcon(_inIcon, className: 'size-4'),
                WText('Stok ekle'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
