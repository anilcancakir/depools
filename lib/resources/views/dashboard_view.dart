import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart'
    show ButtonIntent, MSButton, MSEmptyState, MSPageScaffold;

import '../../ui/components/list_footer/list_footer.dart';
import '../../ui/components/lot_row/lot_row.dart';
import '../../ui/components/movement_row/movement_row.dart';
import '../../ui/components/product_row/product_row.dart';
import '../../ui/components/section_card/section_card.dart';
import '../../ui/components/setup_step/setup_step.dart';
import '../../ui/components/stat_card/stat_card.dart';
import 'products/activity_fixtures.dart';
import 'products/expiring_fixtures.dart';
import 'products/product_fixtures.dart';
import 'products/running_low_fixtures.dart';
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
class DashboardView extends StatelessWidget {
  static const IconData _iconScan = Icons.qr_code_scanner_outlined;
  static const IconData _iconAssistant = Icons.auto_awesome_outlined;
  static const IconData _iconCount = Icons.checklist_outlined;
  static const IconData _iconCalm = Icons.check_circle_outline;

  /// How many rows a dashboard card shows before it defers to its own screen.
  static const int _rowCap = 3;

  /// Whether the tenant has any stock at all.
  ///
  /// **"Caught up" and "not started" are not the same empty screen, and treating them as one was a
  /// defect this screen introduced (D64).** Both produce four zeroes, and the first version showed
  /// the same calm `Bekleyen iş yok` for both. To someone who signed up ten seconds ago that reads
  /// as the app claiming their work is done, which is the least useful thing it could say at the
  /// only moment they are deciding whether to continue.
  final bool hasStock;

  /// Creates the [DashboardView].
  const DashboardView({super.key}) : hasStock = true;

  /// Creates the view for a tenant that has not added anything yet.
  const DashboardView.fresh({super.key}) : hasStock = false;

  @override
  Widget build(BuildContext context) {
    final List<DatedLot> expired = hasStock ? expiredRows() : const <DatedLot>[];
    final List<DatedLot> approaching = hasStock
        ? approachingByLocation().values.expand((List<DatedLot> rows) => rows).toList()
        : const <DatedLot>[];
    final List<ProductListItem> out = hasStock ? outOfStock : const <ProductListItem>[];
    final List<ProductListItem> low = hasStock ? belowTarget : const <ProductListItem>[];
    final int products = hasStock ? productFixtures.length : 0;
    final int locations = hasStock ? locationOptions.length : 0;
    final bool isCalm = expired.isEmpty && approaching.isEmpty && out.isEmpty && low.isEmpty;

    // A fresh tenant gets a different screen, not a thinner one. The counters, the four cards and
    // the movement history all describe stock, and every one of them would render as a zero or an
    // empty state: six ways of saying the same nothing.
    if (!hasStock) return _buildFirstRun(context);

    return MSPageScaffold(
      title: 'Genel bakış',
      // The scope of everything below, so a counter reading 6 is legible as six OF something.
      subtitle: '$products ürün · $locations konum',
      children: [
        _buildCounters(expired.length, approaching.length, out.length, low.length),
        _buildCapture(context),
        if (isCalm) _buildCalm(),
        if (expired.isNotEmpty || approaching.isNotEmpty) _buildDates(expired, approaching),
        if (out.isNotEmpty || low.isNotEmpty) _buildStock(out, low),
        if (pendingLines.isNotEmpty) _buildShopping(),
        _buildActivity(),
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
      title: 'Depools\'a hoş geldiniz',
      subtitle: 'Stok takibine başlamak için üç adım',
      children: [
        SectionCard(
          label: 'Kurulum',
          count: '3 adım',
          children: [
            SetupStep(
              marker: '1',
              title: 'Konumları tanımlayın',
              description:
                  'Bir ürünün nerede durduğu bilinmeden sayım yapılamaz ve tarih listesi '
                  'depoyu gezerken işe yaramaz.',
              state: SetupStepState.current,
              actionLabel: 'Konum ekle',
              onAction: () => MagicRoute.to('/konumlar'),
            ),
            SetupStep(
              marker: '2',
              title: 'İlk ürünleri ekleyin',
              description: 'Barkodu okutun, fotoğrafını çekin veya asistana yazın.',
              actionLabel: 'Ürün ekle',
              onAction: () => MagicRoute.to('/tara'),
            ),
            SetupStep(
              marker: '3',
              title: 'Hedef seviye belirleyin',
              // The gap named before it bites. The running-low screen's own empty state says the
              // same thing, but by then the user has already opened a screen expecting rows.
              description: 'Hedefi olmayan bir ürün, ne kadar azalırsa azalsın Azalanlar '
                  'listesinde görünmez.',
              actionLabel: 'Ürünlere git',
              onAction: () => MagicRoute.to('/urunler'),
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
          child: StatCard(label: 'Süresi geçmiş', value: '$expired', delta: 'parti'),
        ),
        WDiv(
          child: StatCard(
            label: 'Yaklaşan',
            value: '$approaching',
            delta: '$defaultHorizonDays gün içinde',
          ),
        ),
        WDiv(
          child: StatCard(label: 'Stok bitti', value: '$out', delta: 'ürün'),
        ),
        WDiv(
          child: StatCard(label: 'Hedefin altında', value: '$low', delta: 'ürün'),
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
      label: 'Ekle',
      children: [
        WDiv(
          className: 'flex flex-col md:flex-row gap-2 w-full',
          children: [
            _captureButton(context, 'Tara', _iconScan, '/tara', ButtonIntent.primary),
            _captureButton(context, 'Asistana yaz', _iconAssistant, '/asistan'),
            _captureButton(context, 'Sayım yap', _iconCount, '/sayim'),
          ],
        ),
      ],
    );
  }

  /// One capture action.
  ///
  /// Card tone on the two secondary buttons: `secondary` ships `bg-surface-container-high`, which
  /// is DESIGN.md's input fill and reads as a disabled control on a light card.
  Widget _captureButton(
    BuildContext context,
    String label,
    IconData icon,
    String path, [
    ButtonIntent intent = ButtonIntent.secondary,
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
        onPressed: () => MagicRoute.to(path),
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

  /// What is running out of time, expired first.
  ///
  /// Rendered with the same `LotRow` the dates screen uses, so a row here and the row it links to
  /// are the same widget rather than two things that have to be kept looking alike.
  Widget _buildDates(List<DatedLot> expired, List<DatedLot> approaching) {
    final List<DatedLot> rows = <DatedLot>[...expired, ...approaching];

    return SectionCard(
      label: 'Tarihler',
      count: '${rows.length} parti',
      action: _seeAll('/tarihler', 'Tüm tarihleri gör'),
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
        _hiddenCount(rows.length, 'parti'),
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
      label: 'Azalanlar',
      count: '${rows.length} ürün',
      action: _seeAll('/azalanlar', 'Tümünü gör'),
      children: [
        for (final ProductListItem p in rows.take(_rowCap)) _productRow(p),
        _hiddenCount(rows.length, 'ürün'),
      ],
    );
  }

  /// One short product, rendered by the list screen's own row.
  Widget _productRow(ProductListItem product) {
    final (String primary, String? primaryUnit) = product.primaryFigure;
    final (String, String?)? remainder = product.remainderFigure;

    return ProductRow(
      name: product.name,
      meta: 'Hedef ${product.parLevel} ${product.unit}',
      amount: product.amount,
      formatted: primary,
      unit: primaryUnit,
      remainderFormatted: remainder?.$1,
      remainderUnit: remainder?.$2,
      parLevel: product.parLevel,
      onTap: () => MagicRoute.to('/azalanlar'),
    );
  }

  /// What to buy, as a count and a way in.
  ///
  /// Deliberately NOT three shopping rows. The list is a document the user works through with a
  /// phone in one hand, and a partial copy of it invites ticking items off in the wrong place;
  /// the other three cards are facts, which a partial view of is still useful.
  Widget _buildShopping() {
    return SectionCard(
      label: 'Alışveriş listesi',
      count: '${pendingLines.length} satır',
      action: _seeAll('/alisveris', 'Listeyi aç'),
      children: [
        WText(
          'Azalan ve tarihi yaklaşan ürünlerden derlendi. Kalemler listede işaretlenir.',
          className: 'text-sm text-fg-muted',
        ),
      ],
    );
  }

  /// What the app did last, so an automatic write is never a surprise.
  Widget _buildActivity() {
    final List<ActivityFixture> rows = activityEntries;

    return SectionCard(
      label: 'Son hareketler',
      count: '${rows.length} hareket',
      collapsible: true,
      children: [
        for (final ActivityFixture entry in rows.take(_rowCap))
          MovementRow(
            reason: entry.product,
            deltaAmount: entry.deltaAmount,
            delta: entry.delta,
            unit: entry.unit,
            meta: entry.meta,
            direction: entry.direction,
            note: entry.note,
          ),
        _hiddenCount(rows.length, 'hareket'),
      ],
    );
  }

  /// Nothing needs attention, which is the outcome the product is for.
  ///
  /// A dashboard with four zeroes and no cards under them looks broken rather than calm, so the
  /// good state says so in words. It is reachable: every counter here is derived, so a tenant who
  /// has cleared their dates and restocked lands on exactly this.
  Widget _buildCalm() {
    return SectionCard(
      label: 'Durum',
      children: [
        WDiv(
          className: 'w-full',
          child: const MSEmptyState(
            icon: _iconCalm,
            title: 'Bekleyen iş yok',
            description:
                'Süresi geçen, tarihi yaklaşan veya hedefin altına düşen ürün yok. '
                'Yeni bir giriş için yukarıdaki eylemleri kullanın.',
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
  Widget _hiddenCount(int total, String noun) {
    if (total <= _rowCap) return const SizedBox.shrink();

    return ListFooter(
      state: ListFooterState.end,
      pageSize: _rowCap,
      totalLabel: '+${total - _rowCap} $noun',
    );
  }
}
