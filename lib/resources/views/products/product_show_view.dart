import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart'
    show
        MSPageHeader,
        MSButton,
        ButtonIntent,
        ButtonSize,
        MSDropdownMenu,
        MSDropdownMenuItem;

import '../../../ui/components/expiry_badge/expiry_badge.dart';
import '../../../ui/components/location_stock_row/location_stock_row.dart';
import '../../../ui/components/lot_row/lot_row.dart';
import '../../../ui/components/movement_row/movement_row.dart';
import '../../../ui/components/quantity/quantity.dart';
import '../../../ui/components/section_header/section_header.dart';
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

  /// Creates the [ProductShowView].
  const ProductShowView({super.key});

  @override
  Widget build(BuildContext context) {
    return WDiv(
      className: 'w-full h-full overflow-y-auto bg-surface',
      scrollPrimary: true,
      child: WDiv(
        className: 'flex flex-col gap-5 p-4 md:px-5',
        children: [
          _buildHeader(),
          _buildIdentity(),
          _buildBarcodes(),
          _buildStockSummary(),
          _buildForecast(),
          _buildLocations(),
          _buildLots(),
          _buildMovements(),
          _buildPrimaryAction(),
        ],
      ),
    );
  }

  /// The page title, with the two secondary actions as icon buttons.
  ///
  /// "Taşı" and "Etiket" live here rather than beside the primary button at the
  /// bottom. Three buttons in one row does not fit a phone, and it left the screen
  /// with no clear primary. As icons in the header they stay reachable without
  /// competing, and each carries a `semanticLabel` because an icon-only control is
  /// nameless to a screen reader otherwise.
  Widget _buildHeader() {
    return MSPageHeader(
      title: 'Pınar Süt Tam Yağlı 1 lt',
      subtitle: 'Pınar',
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
    return WDiv(
      className: 'flex flex-col gap-1 p-4 rounded-lg bg-surface-container',
      children: [
        const SectionHeader(label: 'Barkodlar', count: '2 kod'),
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
            const Quantity(amount: 5, formatted: '5', unit: 'adet', size: QuantitySize.lg),
          ],
        ),
        WDiv(
          className: 'flex flex-col items-end gap-1',
          children: [
            WText('En yakın tarih', className: 'text-xs text-fg-muted'),
            const ExpiryBadge(label: 'Süresi geçti', daysUntilExpiry: -1),
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
  Widget _buildForecast() {
    return const WDiv(
      className: 'flex flex-row gap-3',
      children: [
        WDiv(
          className: 'flex-1',
          child: StatCard(label: 'Hedef seviye', value: '6 adet', delta: 'sen belirledin'),
        ),
        WDiv(
          className: 'flex-1',
          child: StatCard(
            label: 'Tüketim tahmini',
            value: 'Henüz yok',
            delta: '9 hareket, 10 gerekiyor',
          ),
        ),
      ],
    );
  }

  Widget _buildLocations() {
    return const WDiv(
      className: 'flex flex-col gap-1 p-4 rounded-lg bg-surface-container',
      children: [
        SectionHeader(label: 'Konumlar', count: '2 konum'),
        LocationStockRow(
          path: 'Mutfak › Buzdolabı',
          amount: 3,
          quantity: '3',
          unit: 'adet',
          lotsLabel: '3 parti',
          expiryLabel: 'Süresi geçti',
          daysUntilExpiry: -1,
        ),
        LocationStockRow(
          path: 'Kiler › Raf 2',
          amount: 2,
          quantity: '2',
          unit: 'adet',
          lotsLabel: '1 parti',
          expiryLabel: '9 gün',
          daysUntilExpiry: 9,
        ),
      ],
    );
  }

  Widget _buildLots() {
    return const WDiv(
      className: 'flex flex-col gap-1 p-4 rounded-lg bg-surface-container',
      children: [
        SectionHeader(label: 'Partiler', count: '4 parti'),
        LotRow(
          remainingAmount: 1,
          remaining: '1',
          unit: 'adet',
          expiryLabel: 'Süresi geçti',
          daysUntilExpiry: -1,
          receivedLabel: '28 Tem alındı',
        ),
        LotRow(
          remainingAmount: 1,
          remaining: '1',
          unit: 'adet',
          expiryLabel: '2 gün',
          daysUntilExpiry: 2,
          receivedLabel: '3 Ağu alındı',
          lotCode: 'L2408-33',
        ),
        LotRow(
          remainingAmount: 2,
          remaining: '2',
          unit: 'adet',
          expiryLabel: '9 gün',
          daysUntilExpiry: 9,
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
    return WDiv(
      className: 'flex flex-col gap-1 p-4 rounded-lg bg-surface-container',
      children: [
        SectionHeader(
          label: 'Hareketler',
          count: '9 kayıt',
          action: MSButton(
            onPressed: () {},
            intent: ButtonIntent.ghost,
            size: ButtonSize.sm,
            className: 'min-h-11 justify-center',
            child: const WDiv(
              className: 'flex flex-row items-center gap-0.5',
              children: [WText('Tümü'), WIcon(_chevronIcon, className: 'size-4')],
            ),
          ),
        ),
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
              children: [WIcon(_outIcon, className: 'size-4'), WText('Stok çıkar')],
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
              children: [WIcon(_inIcon, className: 'size-4'), WText('Stok ekle')],
            ),
          ),
        ),
      ],
    );
  }
}
