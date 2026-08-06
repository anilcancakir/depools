import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart'
    show MSPageHeader, MSButton, ButtonIntent, ButtonSize, MSEmptyState;

import '../../../ui/components/product_row/product_row.dart';
import '../../../ui/components/section_header/section_header.dart';

/// Stock list: every product the tenant holds, and the home surface in inventory mode.
///
/// This screen is where a new user lands, so `product.md`'s first success criterion
/// lives here: ten items into stock in under five minutes without reading anything.
/// That is why the empty state offers the three fastest capture paths rather than a
/// "Create product" button, and why the paths are ordered by speed rather than by how
/// much control they give.
///
/// **It is deliberately built almost entirely from what the product detail screen
/// already needed.** `SectionHeader`, `Quantity` and `ExpiryBadge` come across
/// unchanged, and only `ProductRow` is new, which is the argument for having designed
/// the detail screen first: its primitives paid for this one. The reverse order would
/// have meant designing the lot and location rows twice.
///
/// **The action-placement rule gains a distinction here, and both screens are better
/// for it.** `ProductShowView` puts its frequent mutations in a footer, and this screen
/// first copied that with an "Ürün ekle" button at the bottom. Wrong: on a LIST,
/// creating a new item is the canonical header action, the way iOS puts a plus in the
/// nav bar. The footer is for acting on the thing you are already looking at, which is
/// what stock in and out are on a detail screen.
///
/// So: **header plus creates a new item in this collection, footer acts on the item you
/// are viewing.** Card headers still navigate only, and search and filter sit at the
/// top because they change what you look at rather than the data.
///
/// Rendered from fixtures. Wiring it to a `ProductController` with `fetchList` is the
/// next step; the fixtures stay as the preview's data source afterwards.
@immutable
class ProductIndexView extends StatelessWidget {
  static const IconData _searchIcon = Icons.search_outlined;
  static const IconData _filterIcon = Icons.filter_list_outlined;
  static const IconData _scanIcon = Icons.qr_code_scanner_outlined;
  static const IconData _receiptIcon = Icons.receipt_long_outlined;
  static const IconData _photoIcon = Icons.photo_camera_outlined;
  static const IconData _addIcon = Icons.add_outlined;

  /// Whether the tenant has no products at all yet.
  final bool isEmpty;

  /// Creates the [ProductIndexView].
  const ProductIndexView({super.key}) : isEmpty = false;

  /// Creates the view for a tenant with no products yet.
  const ProductIndexView.empty({super.key}) : isEmpty = true;

  @override
  Widget build(BuildContext context) {
    return WDiv(
      className: 'w-full h-full overflow-y-auto bg-surface',
      scrollPrimary: true,
      child: WDiv(
        className: 'flex flex-col gap-4 p-4 md:px-5',
        children: [
          _buildHeader(),
          if (!isEmpty) _buildSearch(),
          if (isEmpty) _buildEmpty() else ..._buildList(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return MSPageHeader(
      title: 'Stok',
      subtitle: isEmpty ? null : 'Mutfak Deposu · 42 ürün',
      actions: [
        MSButton(
          onPressed: () {},
          intent: ButtonIntent.ghost,
          className: 'min-h-11 min-w-11 justify-center',
          semanticLabel: 'Barkod tara',
          child: const WIcon(_scanIcon),
        ),
        MSButton(
          onPressed: () {},
          className: 'min-h-11 min-w-11 justify-center',
          semanticLabel: 'Ürün ekle',
          child: const WIcon(_addIcon),
        ),
      ],
    );
  }

  /// Search and filter, side by side.
  ///
  /// Both are navigation rather than mutation, which is why they sit here at the top
  /// instead of in a card header: they change what you are looking at, not the data.
  Widget _buildSearch() {
    return WDiv(
      className: 'flex flex-row items-center gap-2',
      children: [
        WDiv(
          className: '''
            flex flex-row items-center gap-2 flex-1 min-w-0
            bg-surface-container-high rounded-md px-3 min-h-11
          ''',
          children: [
            const WIcon(_searchIcon, className: 'size-4 text-fg-muted'),
            WText('Ara: ürün, konum, barkod', className: 'text-sm text-fg-muted truncate'),
          ],
        ),
        MSButton(
          onPressed: () {},
          intent: ButtonIntent.secondary,
          className: 'min-h-11 min-w-11 justify-center',
          semanticLabel: 'Filtrele',
          child: const WIcon(_filterIcon),
        ),
      ],
    );
  }

  /// The first thing a new user sees, so it offers the fastest routes in, not a form.
  ///
  /// Ordered by speed rather than by control: a receipt photo enters many products at
  /// once, a barcode enters one with its details filled, a photo enters one that has
  /// no barcode, and typing is last because it is the slowest even though it is the
  /// most obvious. `.claude/rules/design.md` requires the call to action; the ordering
  /// is what makes it useful rather than decorative.
  Widget _buildEmpty() {
    return WDiv(
      // `items-stretch` is load-bearing. MSEmptyState's root already carries
      // `items-center text-center`, but Wind's flex-col defaults its cross axis to
      // start, so without this the block sized to its content and sat against the
      // left edge of the card while looking internally centred. The buttons below
      // were never affected because `fullWidth` wraps them in a full-width box.
      className: 'flex flex-col items-stretch gap-3 p-4 rounded-lg bg-surface-container',
      children: [
        MSEmptyState(
          icon: _receiptIcon,
          title: 'Henüz ürün yok',
          description: 'En hızlısı fiş fotoğrafı: bir alışverişin tamamı tek karede girer. '
              'Barkod tararsan ürün bilgileri kendiliğinden dolar.',
        ),
        WDiv(
          className: 'flex flex-col gap-2',
          children: [
            MSButton(
              onPressed: () {},
              fullWidth: true,
              className: 'justify-center gap-2',
              child: const WDiv(
                className: 'flex flex-row items-center gap-2',
                children: [WIcon(_receiptIcon, className: 'size-4'), WText('Fiş fotoğrafı çek')],
              ),
            ),
            WDiv(
              className: 'flex flex-row gap-2',
              children: [
                WDiv(
                  className: 'flex-1',
                  child: MSButton(
                    onPressed: () {},
                    intent: ButtonIntent.secondary,
                    fullWidth: true,
                    className: 'justify-center gap-2',
                    child: const WDiv(
                      className: 'flex flex-row items-center gap-2',
                      children: [WIcon(_scanIcon, className: 'size-4'), WText('Barkod tara')],
                    ),
                  ),
                ),
                WDiv(
                  className: 'flex-1',
                  child: MSButton(
                    onPressed: () {},
                    intent: ButtonIntent.secondary,
                    fullWidth: true,
                    className: 'justify-center gap-2',
                    child: const WDiv(
                      className: 'flex flex-row items-center gap-2',
                      children: [WIcon(_photoIcon, className: 'size-4'), WText('Fotoğraftan')],
                    ),
                  ),
                ),
              ],
            ),
            MSButton(
              onPressed: () {},
              intent: ButtonIntent.ghost,
              fullWidth: true,
              className: 'justify-center',
              child: const WText('Elle gir'),
            ),
          ],
        ),
      ],
    );
  }

  /// The list, grouped so the thing that needs attention comes first.
  ///
  /// Expiring items lead, because that is the one section a cafe opens this screen for
  /// daily and it needs no forecast to be correct, only a date comparison. Everything
  /// else follows alphabetically. `forecasting.md` puts "expiring soon" first among the
  /// three surfaces for the same reason.
  List<Widget> _buildList() {
    return [
      WDiv(
        className: 'flex flex-col gap-1 p-4 rounded-lg bg-surface-container',
        children: [
          const SectionHeader(label: 'Dikkat gerekiyor', count: '3 ürün'),
          ProductRow(
            name: 'Pınar Süt Tam Yağlı 1 lt',
            meta: 'Pınar · Buzdolabı, Kiler',
            amount: 5,
            formatted: '5',
            unit: 'adet',
            expiryLabel: 'Süresi geçti',
            daysUntilExpiry: -1,
            onTap: () {},
          ),
          ProductRow(
            name: 'Bulgur',
            meta: 'Duru · Çekmece 2',
            amount: 0.8,
            formatted: '0,80',
            unit: 'kg',
            expiryLabel: '2 gün',
            daysUntilExpiry: 2,
            onTap: () {},
          ),
          ProductRow(
            name: 'Kıyma',
            meta: 'Dana · Derin dondurucu',
            amount: 0,
            formatted: '0',
            unit: 'kg',
            onTap: () {},
          ),
        ],
      ),
      WDiv(
        className: 'flex flex-col gap-1 p-4 rounded-lg bg-surface-container',
        children: [
          SectionHeader(
            label: 'Tüm ürünler',
            count: '42 ürün',
            action: MSButton(
              onPressed: () {},
              intent: ButtonIntent.ghost,
              size: ButtonSize.sm,
              className: 'min-h-11 axis-min',
              child: const WDiv(
                className: 'flex flex-row items-center gap-0.5 axis-min',
                children: [WText('Tümü'), WIcon(Icons.chevron_right_outlined, className: 'size-4')],
              ),
            ),
          ),
          ProductRow(
            name: 'Ayçiçek Yağı 5 lt',
            meta: 'Yudum · Kiler › Raf 2',
            amount: 2,
            formatted: '2',
            unit: 'adet',
            onTap: () {},
          ),
          ProductRow(
            name: 'Yoğurt 2 kg',
            meta: 'Sütaş · Buzdolabı',
            amount: 1,
            formatted: '1',
            unit: 'adet',
            expiryLabel: '9 gün',
            daysUntilExpiry: 9,
            onTap: () {},
          ),
          ProductRow(
            name: 'Un',
            meta: 'Söke · Kiler › Raf 1',
            amount: 12.5,
            formatted: '12,50',
            unit: 'kg',
            onTap: () {},
          ),
        ],
      ),
    ];
  }
}
