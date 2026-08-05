import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart'
    show MSPageHeader, MSButton, ButtonIntent, ButtonSize;

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
/// Currently rendered from the fixtures below rather than a controller. Wiring it to
/// a `ProductController` is the next step; the fixtures stay afterwards as the
/// preview's data source so the catalog keeps working without a backend.
@immutable
class ProductShowView extends StatelessWidget {
  static const IconData _imagePlaceholderIcon = Icons.photo_outlined;
  static const IconData _moveIcon = Icons.swap_horiz_outlined;
  static const IconData _labelIcon = Icons.qr_code_2_outlined;
  static const IconData _scanIcon = Icons.barcode_reader;

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
  Widget _buildBarcodes() {
    return WDiv(
      className: 'flex flex-col gap-1 p-4 rounded-lg bg-surface-container',
      children: [
        SectionHeader(
          label: 'Barkodlar',
          count: '2 kod',
          action: MSButton(
            onPressed: () {},
            intent: ButtonIntent.ghost,
            size: ButtonSize.sm,
            className: 'min-h-11 min-w-11 justify-center',
            semanticLabel: 'Barkod tara',
            child: const WIcon(_scanIcon),
          ),
        ),
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
            child: const WText('Tümü'),
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

  /// One primary action, full width, on its own row.
  ///
  /// Recording a movement is what a user opens this screen to do most often, so it
  /// is the only filled button on the page. It gets its own row because a phone
  /// cannot fit three buttons side by side, and the earlier attempt at that left the
  /// label hanging off the left edge of a stretched button instead of centred.
  Widget _buildPrimaryAction() {
    return WDiv(
      className: 'pb-2',
      child: MSButton(
        onPressed: () {},
        fullWidth: true,
        child: const WText('Hareket ekle'),
      ),
    );
  }
}
