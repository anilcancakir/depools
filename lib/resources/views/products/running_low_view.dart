import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart' show MSPageScaffold, MSEmptyState;

import '../../../ui/components/product_row/product_row.dart';
import '../../../ui/components/section_card/section_card.dart';
import 'product_fixtures.dart';
import 'running_low_fixtures.dart';
import 'stock_in_sheet.dart';

/// What is short: the second of `forecasting.md`'s three surfaces.
///
/// ### Why this is not the shopping list
///
/// The two show almost the same rows and answer different questions. This is the
/// DIAGNOSIS: what is short, how sure the app is, and why. The shopping list is the ACTION:
/// what to buy, tick off, and reconcile against a receipt. So the numbers live here and a
/// sentence lives there (D46 turns the tier into the shape of that sentence), and the rows
/// here are not tickable, dismissable or reorderable, because a diagnosis is not a document
/// the user edits.
///
/// The containment runs one way and a test locks it in: every product here is on the
/// shopping list, and the shopping list also carries expiring and manual rows, so it is a
/// superset. `test/running_low_test.dart` asserts both directions of that, because this app
/// has already shipped a list and a detail page disagreeing about one product.
///
/// ### The tier IS the structure (D57)
///
/// `forecasting.md` gates hard on history: below roughly ten movements, no forecast at all.
/// Rather than hiding that behind a uniform list, the tier is the group heading, and each
/// group says in one line what it is allowed to claim. A user who wants to know why the app
/// is confident about the bulgur and vague about the milk can read it off the screen instead
/// of taking the ranking on faith.
///
/// Days of cover appears only in the top group, because that is the only tier where it
/// exists. It is not omitted from the others as an editorial choice; there is no number.
///
/// ### Out of stock is its own group, not the worst kind of low
///
/// Zero is not a degree of short: there is nothing left to ration and no question of how
/// soon to act. It leads, it does not fold, and it is ordered above the tiers so a
/// well-forecast product with four days of cover never outranks something already gone.
@immutable
class RunningLowView extends StatelessWidget {
  static const IconData _emptyIcon = Icons.inventory_outlined;

  /// Whether anything is short.
  ///
  /// Nothing short is the good outcome, like an empty shopping list, and must read as one.
  final bool hasRows;

  /// Creates the [RunningLowView].
  const RunningLowView({super.key}) : hasRows = true;

  /// Creates the view with nothing short.
  const RunningLowView.empty({super.key}) : hasRows = false;

  /// What each tier is allowed to say, in the user's own terms.
  static String _tierNote(ForecastTier tier) => switch (tier) {
    ForecastTier.forecast => 'En az 10 hareket · tüketim hızı hesaplanıyor',
    ForecastTier.rough => 'Geçmiş az · sadece kaba bir aralık',
    ForecastTier.target => 'Geçmiş yok · sadece hedef seviye',
  };

  static String _tierLabel(ForecastTier tier) => switch (tier) {
    ForecastTier.forecast => 'Tahmine göre',
    ForecastTier.rough => 'Geçmişi az',
    ForecastTier.target => 'Hedefe göre',
  };

  @override
  Widget build(BuildContext context) {
    final List<ProductListItem> out = hasRows ? outOfStock : const [];
    final int short = hasRows ? belowTarget.length : 0;

    return MSPageScaffold(
      title: 'Azalanlar',
      subtitle: hasRows ? '$short ürün · ${out.length} stok bitti' : 'Hedefin altında ürün yok',
      children: [
        if (out.isNotEmpty) _buildOut(context, out),
        for (final ForecastTier tier in ForecastTier.values)
          if (hasRows && lowInTier(tier).isNotEmpty) _buildTier(context, tier),
        if (!hasRows) _buildEmpty(),
      ],
    );
  }

  /// Gone entirely. Leads, and does not fold.
  Widget _buildOut(BuildContext context, List<ProductListItem> rows) {
    return SectionCard(
      label: 'Stok bitti',
      count: '${rows.length} ürün',
      children: [for (final ProductListItem p in rows) _buildRow(context, p)],
    );
  }

  /// One certainty tier, with a line saying what it may claim.
  Widget _buildTier(BuildContext context, ForecastTier tier) {
    final List<ProductListItem> rows = lowInTier(tier);

    return SectionCard(
      label: _tierLabel(tier),
      count: '${rows.length} ürün',
      collapsible: true,
      children: [
        // The honesty made legible. Without it the three groups are three unexplained
        // headings and the user has to guess whether the order means anything.
        WText(_tierNote(tier), className: 'text-xs text-fg-muted'),
        for (final ProductListItem p in rows) _buildRow(context, p),
      ],
    );
  }

  /// One row, rendered by the same `ProductRow` the stock list uses.
  ///
  /// **The on-hand figure is NOT restated in the meta line.** A first pass wrote
  /// `'0,80 / 2 kg'` there and got two numbers wrong at once: `formatted` is the WHOLE
  /// count, so a product holding 2.5 read as "2 / 4" and one holding 0.67 read as "0 / 2"
  /// inside a group that is not the out-of-stock group. The row already renders the amount
  /// correctly through `primaryFigure` plus `remainderFigure` (D26: a count and an open
  /// remainder, never one decimal), so the meta carries only what the row does not: the
  /// target, and the cover figure where one exists.
  ///
  /// Cover is suppressed when the product is out. "0 günlük kaldı" beside a group heading
  /// that already says "Stok bitti" is a true statement adding nothing.
  ///
  /// Tapping goes to stock-in rather than to the product page, because the answer to "this
  /// is short" is almost always "I bought some".
  Widget _buildRow(BuildContext context, ProductListItem product) {
    final (String primary, String? primaryUnit) = product.primaryFigure;
    final (String, String?)? remainder = product.remainderFigure;
    final bool showsCover = product.daysOfCover != null && !product.isOut;

    return ProductRow(
      name: product.name,
      meta: [
        'Hedef ${product.parLevel} ${product.unit}',
        if (showsCover) '${product.daysOfCover} günlük kaldı',
      ].join(' · '),
      amount: product.amount,
      formatted: primary,
      unit: primaryUnit,
      remainderFormatted: remainder?.$1,
      remainderUnit: remainder?.$2,
      parLevel: product.parLevel,
      onTap: () => StockInSheet.show(context, product: product),
    );
  }

  /// Nothing short, which is the good outcome.
  Widget _buildEmpty() {
    return SectionCard(
      label: 'Azalanlar',
      children: [
        WDiv(
          // Full width so MSEmptyState's own `items-center` has something to centre in.
          className: 'w-full',
          child: MSEmptyState(
            icon: _emptyIcon,
            title: 'Hedefin altında ürün yok',
            // Names the mechanism, and names the gap: a product with no target can never
            // appear here however low it gets, which is worth saying to someone looking at
            // an empty screen with a half-empty pantry.
            description:
                'Hedef seviyesi belirlenmiş ürünler o seviyenin altına düştüğünde burada '
                'listelenir. Hedefi olmayan ürünler hiç görünmez.',
          ),
        ),
      ],
    );
  }
}
