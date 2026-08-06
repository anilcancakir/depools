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
import '../../../ui/components/stat_card/stat_card.dart';
import '../../../ui/components/tag/index.dart';

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

  /// Creates the [ProductShowView].
  const ProductShowView({super.key}) : isNew = false;

  /// Creates the view for a product that has no stock or history yet.
  const ProductShowView.newProduct({super.key}) : isNew = true;

  @override
  Widget build(BuildContext context) {
    return MSPageScaffold(
      title: 'Pınar Süt Tam Yağlı 1 lt',
      subtitle: 'Pınar',
      // "Taşı" and "Etiket" live in the header rather than beside the primary button
      // at the bottom. Three buttons in one row does not fit a phone, and it left the
      // screen with no clear primary. As icons in the header they stay reachable
      // without competing, and each carries a `semanticLabel` because an icon-only
      // control is nameless to a screen reader otherwise.
      actions: [
        MSButton(
          onPressed: () {},
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
        _buildPrimaryAction(),
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
                  children: const [
                    Tag(label: 'Süt ürünleri', intent: TagIntent.primary, size: TagSize.sm),
                    Tag(label: 'kahvaltı', size: TagSize.sm),
                    Tag(label: 'soğuk zincir', size: TagSize.sm),
                  ],
                ),
                WText(
                  'Tam yağlı, pastörize inek sütü. 1 litre karton ambalaj, '
                  'açıldıktan sonra buzdolabında 3 gün içinde tüketilmeli.',
                  className: 'text-sm text-fg-muted',
                ),
                // The tenant's own identifier, mono because it is a code the user
                // compares character by character against a shelf label or an order.
                // It sits here rather than in the page subtitle: the subtitle is the
                // brand, and an earlier pass lost the SKU entirely by merging them.
                WText('SKU · SUT-PNR-1L', className: 'font-mono text-xs text-fg-muted'),
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
      count: '2 kod',
      children: [
        _buildBarcodeRow('8690123456789', 'EAN-13 · üretici'),
        _buildBarcodeRow('DP-0042', 'Code128 · bizim bastığımız'),
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
            // The same figure the list row shows for this product, in the same
            // format. It said "5 adet" here while the list said "2 adet + 500 ml",
            // which is the drift this screen is meant to resolve rather than add to:
            // the detail screen is where a user comes to check a number they doubt.
            const Quantity(
              amount: 2.5,
              formatted: '2',
              unit: 'adet',
              remainderFormatted: '500',
              remainderUnit: 'ml',
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
            const ExpiryBadge(label: 'Açık · 2 gün', daysUntilExpiry: 2),
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
            child: StatCard(label: 'Hedef seviye', value: 'Belirlenmedi', delta: 'sen belirle'),
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

    return const WDiv(
      className: 'grid grid-cols-2 md:grid-cols-3 gap-3 items-stretch',
      children: [
        WDiv(
          child: StatCard(label: 'Hedef seviye', value: '4 adet', delta: 'sen belirledin'),
        ),
        WDiv(
          child: StatCard(
            label: 'Tüketim tahmini',
            value: 'Henüz yok',
            delta: '9 hareket, 10 gerekiyor',
          ),
        ),
        WDiv(
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
              description:
                  'Stok eklediğinde hangi konuma koyduğunu sorar, '
                  'sonrasında kendisi önerir.',
            ),
          ),
        ],
      );
    }

    return const SectionCard(
      label: 'Konumlar',
      count: '2 konum',
      children: [
        LocationStockRow(
          path: 'Mutfak › Buzdolabı',
          amount: 1.5,
          quantity: '1',
          unit: 'adet',
          remainderFormatted: '500',
          remainderUnit: 'ml',
          lotsLabel: '2 parti',
          expiryLabel: 'Açık · 2 gün',
          // Two days, not -1. The label was updated when the milk stopped being
          // expired and the day count was not, so this badge rendered in the solid
          // expired tone while the same fact in the lot list below rendered soft. The
          // severity split is the one thing ExpiryBadge cannot be allowed to get
          // wrong: solid means act today, soft means plan.
          daysUntilExpiry: 2,
        ),
        LocationStockRow(
          path: 'Kiler › Raf 2',
          amount: 1,
          quantity: '1',
          unit: 'adet',
          lotsLabel: '1 parti',
          expiryLabel: '12 gün',
          daysUntilExpiry: 12,
        ),
      ],
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
                  'Her stok girişi bir parti açar. Son kullanma tarihi girersen '
                  'önce bitmesi gerekeni buradan takip edersin.',
            ),
          ),
        ],
      );
    }

    // The lots have to SUM to the headline, and they did not: the list showed
    // "2 adet + 500 ml" while these added up to 4.5 and included an expired carton
    // the list knew nothing about. Hand-written fixtures across two screens is how
    // that happens, and the structural fix is one source for both. Until then these
    // numbers are checked by hand and the arithmetic is written down:
    //
    //   0.5 (open) + 1 + 1 = 2.5 adet, matching the headline and the two locations
    //   (fridge 1.5 = the open one plus a sealed, pantry 1).
    //
    // The depleted lot is excluded from that sum on purpose. It is at zero and stays
    // visible as the evidence behind the consumption history.
    return const SectionCard(
      label: 'Partiler',
      count: '4 parti',
      children: [
        // The open lot leads, and it is the reason this list exists rather than just
        // a total. The row above reads "2 adet + 500 ml"; this says WHICH 500 ml,
        // opened when, and that it now has two days rather than the week its printed
        // date still shows. That gap is the whole of D27.
        LotRow(
          remainingAmount: 0.5,
          remaining: '500',
          unit: 'ml',
          isOpen: true,
          expiryLabel: '2 gün',
          daysUntilExpiry: 2,
          openedLabel: '5 Ağu açıldı · kutuda 12 Ağu yazıyor',
        ),
        LotRow(
          remainingAmount: 1,
          remaining: '1',
          unit: 'adet',
          expiryLabel: '6 gün',
          daysUntilExpiry: 6,
          receivedLabel: '3 Ağu alındı',
          lotCode: 'L2408-33',
        ),
        LotRow(
          remainingAmount: 1,
          remaining: '1',
          unit: 'adet',
          expiryLabel: '12 gün',
          daysUntilExpiry: 12,
          receivedLabel: '5 Ağu alındı',
        ),
        LotRow(
          remainingAmount: 0,
          remaining: '0',
          unit: 'adet',
          expiryLabel: '12 Tem',
          daysUntilExpiry: -24,
          receivedLabel: '8 Tem alındı',
          isDepleted: true,
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
                  'Aşağıdaki iki butonla ilk girişini ya da çıkışını kaydet. '
                  'Tüketim tahmini için birikmesi gereken geçmiş buradan başlar.',
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
  Widget _buildPrimaryAction() {
    return WDiv(
      className: 'flex flex-row gap-3 pb-2',
      children: [
        WDiv(
          className: 'flex-1',
          child: MSButton(
            onPressed: () {},
            fullWidth: true,
            className: 'justify-center gap-2',
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
          className: 'flex-1',
          child: MSButton(
            onPressed: () {},
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
