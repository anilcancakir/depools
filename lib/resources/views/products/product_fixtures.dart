import 'package:flutter/foundation.dart';

import '../../../app/models/product_filter.dart';
import 'product_filter_sheet.dart';

/// One product as the stock list needs it.
///
/// The list was built from hardcoded `ProductRow` widgets, which was fine while it
/// only had to render. It cannot stay that way now that the screen filters: a filter
/// over widgets is not a filter, and the count in the sheet's apply button has to
/// come from the same source the list renders, or the two will disagree.
///
/// This is deliberately not a `MagicModel`. It is the shape the eventual
/// `ProductController` will hand the view, so building it now means the controller
/// swap replaces where the rows come from and touches nothing else. The fixtures
/// stay afterwards as the preview catalog's data source.
@immutable
class ProductListItem {
  /// Product name.
  final String name;

  /// Brand, if known.
  final String? brand;

  /// The ids of every location holding stock of this product.
  final Set<String> locationIds;

  /// The already-joined location text for the row's meta line.
  final String locationSummary;

  /// Category id.
  final String? categoryId;

  /// Tags.
  final Set<String> tags;

  /// Total on hand across every location.
  final num amount;

  /// The already-formatted total for the active locale.
  final String formatted;

  /// Base unit.
  final String unit;

  /// The user-set target level, used for the below-par test. Null means unset, and
  /// an unset target can never be "below par": that state has to mean something the
  /// user chose, or every product with a little stock would report as running low.
  final num? parLevel;

  /// Days until the earliest lot expiry. Null when nothing tracks expiry.
  final int? daysUntilExpiry;

  /// The product's shelf life in days, from `products.default_shelf_life_days`.
  ///
  /// Drives [expiryThresholdDays]. Null means unknown, which falls back to the
  /// neutral default rather than to no warning: a product with an expiry date and no
  /// declared shelf life still has to be able to warn.
  final int? shelfLifeDays;

  /// The already-formatted expiry label for the row.
  final String? expiryLabel;

  /// Creates a [ProductListItem].
  const ProductListItem({
    required this.name,
    required this.amount,
    required this.formatted,
    required this.unit,
    this.brand,
    this.locationIds = const {},
    this.locationSummary = '',
    this.categoryId,
    this.tags = const {},
    this.parLevel,
    this.daysUntilExpiry,
    this.expiryLabel,
    this.shelfLifeDays,
  });

  /// The neutral window used when a product declares no shelf life.
  static const int fallbackThresholdDays = 7;

  /// The longest warning window, in days.
  ///
  /// Without a ceiling the proportion runs away on long-life goods: a tin with a two
  /// year shelf life would start warning 146 days out, which is noise rather than
  /// signal. Two months is the point where a tin becomes worth acting on.
  static const int maxThresholdDays = 60;

  /// How many days before expiry this product starts needing attention.
  ///
  /// **Derived per product rather than fixed**, which is the decision recorded in
  /// `open-decisions.md`. One global number cannot be right for both milk and flour:
  /// seven days always warns about a five-day carton and never warns about a tin.
  ///
  /// The window is the last fifth of the shelf life, floored at one day and capped
  /// at [maxThresholdDays]. Milk (5 days) warns 1 day out; a tin (730 days) warns 60
  /// days out. Those two ends are what the proportion was chosen to satisfy.
  int get expiryThresholdDays {
    final int life = shelfLifeDays ?? fallbackThresholdDays * 5;
    return (life * 0.2).round().clamp(1, maxThresholdDays);
  }

  /// The meta line under the name: brand and where it is.
  String? get meta {
    final List<String> parts = <String>[?brand, if (locationSummary.isNotEmpty) locationSummary];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  /// Whether this product needs attention.
  ///
  /// Four conditions, and the order of that list is the point: **out of stock and
  /// below par come first, because they are the only ones a product without an expiry
  /// date can trigger.** An earlier version tested expiry and zero stock only, which
  /// meant a workshop tracking spare parts or a shop tracking chargers got an empty
  /// attention section no matter how low it ran. This is not a food app; expiry is one
  /// signal among several rather than the organising one.
  ///
  /// It is deliberately the same predicate the built-in saved filters use, so the
  /// section and the chips cannot disagree. They did once: the section hardcoded two
  /// days while the filter used seven, so a product could pass "Yakında bitecek" and
  /// be missing from the section that exists to surface exactly that.
  bool get needsAttention => amount == 0 || isBelowPar || isExpired || isExpiringSoon;

  /// Whether stock has fallen to or below the user's own target level.
  ///
  /// Requires a target the user actually set. Without the null guard, every product
  /// holding a small amount would report as running low, and "below par" has to mean
  /// something someone chose.
  bool get isBelowPar => parLevel != null && amount > 0 && amount <= parLevel!;

  /// Whether the earliest lot is already past its date.
  bool get isExpired => daysUntilExpiry != null && daysUntilExpiry! < 0;

  /// Whether the earliest lot falls inside this product's own warning window.
  ///
  /// Already expired is NOT expiring soon. They are different situations and the user
  /// picks one of them; folding them together would make "Yakında bitecek" include
  /// things that went off last month.
  bool get isExpiringSoon =>
      daysUntilExpiry != null && daysUntilExpiry! >= 0 && daysUntilExpiry! <= expiryThresholdDays;

  /// Whether this product satisfies [filter].
  ///
  /// Every axis is an AND, and an empty axis is not a constraint. Free text matches
  /// name or brand, case-insensitively: a user typing "pinar" should find "Pınar",
  /// so the comparison is lowercased on both sides.
  bool matches(ProductFilter filter) {
    if (filter.query.isNotEmpty) {
      final String needle = filter.query.toLowerCase();
      final bool hit =
          name.toLowerCase().contains(needle) || (brand?.toLowerCase().contains(needle) ?? false);
      if (!hit) return false;
    }

    if (filter.locationIds.isNotEmpty && locationIds.intersection(filter.locationIds).isEmpty) {
      return false;
    }

    if (filter.categoryIds.isNotEmpty && !filter.categoryIds.contains(categoryId)) {
      return false;
    }

    if (filter.tags.isNotEmpty && tags.intersection(filter.tags).isEmpty) return false;

    if (filter.brands.isNotEmpty && !filter.brands.contains(brand)) return false;

    switch (filter.stockState) {
      case StockStateFilter.any:
        break;
      case StockStateFilter.outOfStock:
        if (amount != 0) return false;
      case StockStateFilter.belowPar:
        if (!isBelowPar) return false;
      case StockStateFilter.inStock:
        if (amount == 0) return false;
    }

    switch (filter.expiry) {
      case ExpiryFilter.any:
        break;
      case ExpiryFilter.expired:
        if (!isExpired) return false;
      case ExpiryFilter.expiringSoon:
        if (!isExpiringSoon) return false;
    }

    return true;
  }
}

/// The stock list fixtures.
///
/// Chosen so every filter axis has at least one product that passes and one that
/// fails it, which is what makes the filter testable by hand in the catalog: an
/// expired item, one inside its own warning window, one out of stock, one below its
/// target, and several plain ones across several categories and four locations.
///
/// **Two of them deliberately track no expiry at all.** This is not a food app, and a
/// fixture set that was entirely perishable let a real defect through: the attention
/// section tested expiry and zero stock only, so a tenant tracking spare parts or
/// chargers saw an empty section however low they ran. A cable below its target level
/// and a tool at zero are what keep that honest, and they are also what the screen
/// looks like for a workshop rather than a kitchen.
const List<ProductListItem> productFixtures = <ProductListItem>[
  ProductListItem(
    name: 'Pınar Süt Tam Yağlı 1 lt',
    brand: 'Pınar',
    locationIds: {'loc-fridge', 'loc-pantry'},
    locationSummary: 'Buzdolabı, Kiler',
    categoryId: 'cat-dairy',
    tags: {'kahvaltı', 'soğuk zincir'},
    amount: 5,
    formatted: '5',
    unit: 'adet',
    parLevel: 6,
    daysUntilExpiry: -1,
    expiryLabel: 'Süresi geçti',
    // 5 days of shelf life, so the warning window derives to 1 day. Seven days would
    // mean this carton is in the attention list from the moment it is bought.
    shelfLifeDays: 5,
  ),
  ProductListItem(
    name: 'Bulgur',
    brand: 'Duru',
    locationIds: {'loc-drawer'},
    locationSummary: 'Çekmece 2',
    categoryId: 'cat-grain',
    tags: {'bakliyat'},
    amount: 0.8,
    formatted: '0,80',
    unit: 'kg',
    parLevel: 2,
    daysUntilExpiry: 2,
    expiryLabel: '2 gün',
    shelfLifeDays: 365,
  ),
  ProductListItem(
    name: 'Kıyma',
    brand: 'Dana',
    locationIds: {'loc-freezer'},
    locationSummary: 'Derin dondurucu',
    categoryId: 'cat-meat',
    amount: 0,
    formatted: '0',
    unit: 'kg',
    parLevel: 1,
  ),
  ProductListItem(
    name: 'Ayçiçek Yağı 5 lt',
    brand: 'Yudum',
    locationIds: {'loc-pantry'},
    locationSummary: 'Kiler › Raf 2',
    categoryId: 'cat-oil',
    amount: 2,
    formatted: '2',
    unit: 'adet',
  ),
  ProductListItem(
    name: 'Yoğurt 2 kg',
    brand: 'Sütaş',
    locationIds: {'loc-fridge'},
    locationSummary: 'Buzdolabı',
    categoryId: 'cat-dairy',
    tags: {'kahvaltı', 'soğuk zincir'},
    amount: 1,
    formatted: '1',
    unit: 'adet',
    daysUntilExpiry: 9,
    expiryLabel: '9 gün',
    // 21 days of shelf life gives a 4 day window, so 9 days out this is NOT yet in
    // the attention list. The same 9 days on the milk above would be.
    shelfLifeDays: 21,
  ),
  ProductListItem(
    name: 'Un',
    brand: 'Söke',
    locationIds: {'loc-pantry'},
    locationSummary: 'Kiler › Raf 1',
    categoryId: 'cat-grain',
    tags: {'bakliyat'},
    amount: 12.5,
    formatted: '12,50',
    unit: 'kg',
    parLevel: 5,
  ),
  // No expiry, below its target. This is the row a workshop or a shop opens the
  // screen for, and it has to reach the attention section on stock level alone.
  ProductListItem(
    name: 'USB-C Kablo 2 m',
    brand: 'Anker',
    locationIds: {'loc-shelf'},
    locationSummary: 'Depo › Raf A',
    categoryId: 'cat-electronics',
    tags: {'sarf'},
    amount: 3,
    formatted: '3',
    unit: 'adet',
    parLevel: 10,
  ),
  // No expiry, at zero.
  ProductListItem(
    name: 'Tornavida Seti PH2',
    brand: 'Ceta Form',
    locationIds: {'loc-shelf'},
    locationSummary: 'Depo › Raf A',
    categoryId: 'cat-tools',
    amount: 0,
    formatted: '0',
    unit: 'adet',
    parLevel: 2,
  ),
];

/// The location options the filter sheet offers, ordered as the tree reads.
const List<FilterOption> locationOptions = <FilterOption>[
  FilterOption(id: 'loc-fridge', label: 'Buzdolabı'),
  FilterOption(id: 'loc-freezer', label: 'Derin dondurucu'),
  FilterOption(id: 'loc-pantry', label: 'Kiler'),
  FilterOption(id: 'loc-drawer', label: 'Kiler › Çekmece 2'),
  FilterOption(id: 'loc-shelf', label: 'Depo › Raf A'),
];

/// The category options the filter sheet offers.
const List<FilterOption> categoryOptions = <FilterOption>[
  FilterOption(id: 'cat-dairy', label: 'Süt ürünleri'),
  FilterOption(id: 'cat-grain', label: 'Bakliyat ve tahıl'),
  FilterOption(id: 'cat-meat', label: 'Et'),
  FilterOption(id: 'cat-oil', label: 'Yağ'),
  FilterOption(id: 'cat-electronics', label: 'Elektronik'),
  FilterOption(id: 'cat-tools', label: 'El aleti'),
];

/// The tag options the filter sheet offers. A tag is its own id.
const List<FilterOption> tagOptions = <FilterOption>[
  FilterOption(id: 'kahvaltı', label: 'kahvaltı'),
  FilterOption(id: 'soğuk zincir', label: 'soğuk zincir'),
  FilterOption(id: 'bakliyat', label: 'bakliyat'),
  FilterOption(id: 'sarf', label: 'sarf'),
];

/// Resolves a location id to its label, for a filter chip.
String? resolveLocationLabel(String id) {
  for (final FilterOption option in locationOptions) {
    if (option.id == id) return option.label;
  }
  return null;
}

/// Resolves a category id to its label, for a filter chip.
String? resolveCategoryLabel(String id) {
  for (final FilterOption option in categoryOptions) {
    if (option.id == id) return option.label;
  }
  return null;
}
