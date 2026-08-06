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
  });

  /// The meta line under the name: brand and where it is.
  String? get meta {
    final List<String> parts = <String>[?brand, if (locationSummary.isNotEmpty) locationSummary];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  /// Whether this product needs attention: expired, expiring, or out of stock.
  ///
  /// This is the "Dikkat gerekiyor" test, and it is the same three conditions the
  /// three built-in saved filters cover. Keeping it here rather than in the view
  /// means the section and the filters cannot drift apart.
  bool get needsAttention => amount == 0 || (daysUntilExpiry != null && daysUntilExpiry! <= 2);

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
        if (parLevel == null || amount == 0 || amount > parLevel!) return false;
      case StockStateFilter.inStock:
        if (amount == 0) return false;
    }

    switch (filter.expiry) {
      case ExpiryFilter.any:
        break;
      case ExpiryFilter.expired:
        if (daysUntilExpiry == null || daysUntilExpiry! >= 0) return false;
      case ExpiryFilter.expiringSoon:
        // Already expired is not "expiring soon". They are different situations and
        // the user picked one of them: folding expired items into the horizon would
        // make "7 gün içinde bitecek" include things that went off last month.
        if (daysUntilExpiry == null ||
            daysUntilExpiry! < 0 ||
            daysUntilExpiry! > filter.expiringWithinDays) {
          return false;
        }
    }

    return true;
  }
}

/// The stock list fixtures.
///
/// Chosen so every filter axis has at least one product that passes and one that
/// fails it, which is what makes the filter testable by hand in the catalog: an
/// expired item, one expiring inside a week, one out of stock, one below its target,
/// and several plain ones across two categories and four locations.
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
];

/// The location options the filter sheet offers, ordered as the tree reads.
const List<FilterOption> locationOptions = <FilterOption>[
  FilterOption(id: 'loc-fridge', label: 'Buzdolabı'),
  FilterOption(id: 'loc-freezer', label: 'Derin dondurucu'),
  FilterOption(id: 'loc-pantry', label: 'Kiler'),
  FilterOption(id: 'loc-drawer', label: 'Kiler › Çekmece 2'),
];

/// The category options the filter sheet offers.
const List<FilterOption> categoryOptions = <FilterOption>[
  FilterOption(id: 'cat-dairy', label: 'Süt ürünleri'),
  FilterOption(id: 'cat-grain', label: 'Bakliyat ve tahıl'),
  FilterOption(id: 'cat-meat', label: 'Et'),
  FilterOption(id: 'cat-oil', label: 'Yağ'),
];

/// The tag options the filter sheet offers. A tag is its own id.
const List<FilterOption> tagOptions = <FilterOption>[
  FilterOption(id: 'kahvaltı', label: 'kahvaltı'),
  FilterOption(id: 'soğuk zincir', label: 'soğuk zincir'),
  FilterOption(id: 'bakliyat', label: 'bakliyat'),
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
