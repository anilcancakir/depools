import 'package:flutter/foundation.dart';
import 'package:magic/magic.dart';

/// The stock-state axis: how much is on hand relative to the target level.
enum StockStateFilter {
  /// No stock-state constraint.
  any,

  /// Nothing on hand.
  outOfStock,

  /// On hand but at or under `par_level`.
  belowPar,

  /// Above `par_level`.
  inStock,
}

/// The expiry axis.
///
/// Deliberately a small closed set rather than a free date range. "Bitmek üzere" is
/// the question a user actually has.
///
/// **`expiringSoon` carries no number.** The window is derived per product from its
/// shelf life, so the filter cannot name one: seven days always warns about milk and
/// never warns about a tin. See `ProductListItem.expiryThresholdDays`.
enum ExpiryFilter {
  /// No expiry constraint.
  any,

  /// Earliest lot expiry is in the past.
  expired,

  /// Earliest lot expiry is inside the product's own warning window.
  expiringSoon,
}

/// One removable piece of an applied [ProductFilter].
///
/// The filter is a set of typed fields, but the chip row has to render it as a
/// flat list of removable labels, and tapping one has to remove exactly that
/// piece. So each criterion carries both its label and the reduction that drops
/// it, which keeps the "what does × do here" answer in one place instead of in a
/// switch at the call site.
@immutable
class FilterCriterion {
  /// The already-localised chip label, for example `'Kiler'` or `'Süresi geçti'`.
  final String label;

  /// The filter with only this criterion removed.
  final ProductFilter remainder;

  /// Creates a [FilterCriterion].
  const FilterCriterion({required this.label, required this.remainder});
}

/// What the stock list is currently narrowed to.
///
/// Immutable and copy-on-write: every mutation returns a new filter, so a saved
/// filter can never be edited by a caller that merely applied it. The axes are
/// fixed by `docs/depools-system/features/filtering-and-saved-views.md`, which is
/// in turn fixed by the assistant's `search_products` tool: a filter the UI cannot
/// express but the assistant can is a split product.
///
/// Free text lives here alongside the structured axes rather than beside it,
/// because "kilerdeki süt" is one question. Keeping the query out would make a
/// saved filter unable to hold a text term.
@immutable
class ProductFilter {
  /// Free text over name, brand, SKU and barcode.
  final String query;

  /// Selected location ids. A parent id implies its descendants.
  final Set<String> locationIds;

  /// Selected category ids.
  final Set<String> categoryIds;

  /// Selected tags.
  final Set<String> tags;

  /// Selected brands.
  final Set<String> brands;

  /// The stock-state constraint.
  final StockStateFilter stockState;

  /// The expiry constraint.
  final ExpiryFilter expiry;

  /// Creates a [ProductFilter].
  const ProductFilter({
    this.query = '',
    this.locationIds = const {},
    this.categoryIds = const {},
    this.tags = const {},
    this.brands = const {},
    this.stockState = StockStateFilter.any,
    this.expiry = ExpiryFilter.any,
  });

  /// Whether nothing is narrowing the list.
  bool get isEmpty =>
      query.isEmpty &&
      locationIds.isEmpty &&
      categoryIds.isEmpty &&
      tags.isEmpty &&
      brands.isEmpty &&
      stockState == StockStateFilter.any &&
      expiry == ExpiryFilter.any;

  /// Whether something is narrowing the list.
  bool get isActive => !isEmpty;

  /// How many criteria are narrowing the list.
  ///
  /// **A number rather than a colour.** The filter button used to turn `bg-primary` when a filter
  /// was on, which broke two rules at once: it put a second blue fill on a page that already has
  /// one, and it made the state legible only to someone who can see the difference between blue
  /// and grey. DESIGN.md's "colour never carries meaning alone" is written about status and
  /// applies to state exactly as much.
  ///
  /// The count also says more than the colour could. "Filtre var" leaves the user hunting for
  /// which one; `3` tells them how much they are about to clear.
  ///
  /// Each multi-select counts ONE, not one per selection: picking three shelves is one decision
  /// about location, and counting three would make the badge scale with how thorough the user was
  /// rather than with how narrow the list is.
  int get activeCount =>
      (query.isEmpty ? 0 : 1) +
      (locationIds.isEmpty ? 0 : 1) +
      (categoryIds.isEmpty ? 0 : 1) +
      (tags.isEmpty ? 0 : 1) +
      (brands.isEmpty ? 0 : 1) +
      (stockState == StockStateFilter.any ? 0 : 1) +
      (expiry == ExpiryFilter.any ? 0 : 1);

  /// The applied criteria as a flat, removable list.
  ///
  /// Ordered so the coarse constraints read first: text, then state and expiry
  /// (the two that change which products qualify at all), then the multi-selects.
  /// A user scanning the row sees why the list is short before they see which
  /// shelf they picked.
  ///
  /// [resolveLocation], [resolveCategory] and [resolveBrand] turn ids into names.
  /// The filter holds ids because that is what it queries with, and a chip has to
  /// say "Buzdolabı" rather than a uuid. A resolver returning null means the
  /// referenced row is gone, and the criterion is dropped rather than rendered as
  /// a blank chip the user cannot identify or trust.
  List<FilterCriterion> criteria({
    String? Function(String id)? resolveLocation,
    String? Function(String id)? resolveCategory,
    String? Function(String id)? resolveBrand,
  }) {
    final List<FilterCriterion> out = <FilterCriterion>[];

    if (query.isNotEmpty) {
      out.add(
        FilterCriterion(
          label: '"$query"',
          remainder: copyWith(query: ''),
        ),
      );
    }

    if (stockState != StockStateFilter.any) {
      out.add(
        FilterCriterion(
          label: stockStateLabel(stockState),
          remainder: copyWith(stockState: StockStateFilter.any),
        ),
      );
    }

    if (expiry != ExpiryFilter.any) {
      out.add(
        FilterCriterion(
          label: expiryLabel(expiry),
          remainder: copyWith(expiry: ExpiryFilter.any),
        ),
      );
    }

    void addSet(
      Set<String> values,
      String? Function(String id)? resolve,
      ProductFilter Function(Set<String> next) rebuild,
    ) {
      for (final String value in values) {
        final String? label = resolve == null ? value : resolve(value);
        if (label == null) continue;
        out.add(
          FilterCriterion(
            label: label,
            remainder: rebuild(values.where((String v) => v != value).toSet()),
          ),
        );
      }
    }

    addSet(locationIds, resolveLocation, (next) => copyWith(locationIds: next));
    addSet(categoryIds, resolveCategory, (next) => copyWith(categoryIds: next));
    addSet(brands, resolveBrand, (next) => copyWith(brands: next));
    addSet(tags, null, (next) => copyWith(tags: next));

    return out;
  }

  /// The already-localised label for a stock state.
  ///
  /// `any` reads "Tümü" because the only place it appears is a segmented control,
  /// where the axis name is already the group label above it. It is never a chip:
  /// an unconstrained axis is not a criterion. A longer "Tüm stok durumları" took
  /// half the control's width and pushed the other three segments off a phone.
  static String stockStateLabel(StockStateFilter state) => switch (state) {
    StockStateFilter.any => 'Tümü',
    StockStateFilter.outOfStock => 'Stok yok',
    StockStateFilter.belowPar => 'Az kalan',
    StockStateFilter.inStock => 'Stokta',
  };

  /// The already-localised label for an expiry constraint, as a removable chip.
  ///
  /// Says the whole thing, because a chip has to stand alone: read out of context in
  /// a row of criteria, "Yakında" could be almost anything.
  static String expiryLabel(ExpiryFilter expiry) => switch (expiry) {
    ExpiryFilter.any => 'Tümü',
    ExpiryFilter.expired => 'Süresi geçti',
    ExpiryFilter.expiringSoon => 'Yakında bitecek',
  };

  /// The same constraint, shortened for a segmented control.
  ///
  /// The group label ("Son kullanma") already supplies what the chip has to spell
  /// out, so the segment can drop the verb and fit three options on a phone.
  static String expirySegmentLabel(ExpiryFilter expiry) => switch (expiry) {
    ExpiryFilter.any => 'Tümü',
    ExpiryFilter.expired => 'Geçti',
    ExpiryFilter.expiringSoon => 'Yakında',
  };

  /// Returns a copy with the given fields replaced.
  ProductFilter copyWith({
    String? query,
    Set<String>? locationIds,
    Set<String>? categoryIds,
    Set<String>? tags,
    Set<String>? brands,
    StockStateFilter? stockState,
    ExpiryFilter? expiry,
  }) {
    return ProductFilter(
      query: query ?? this.query,
      locationIds: locationIds ?? this.locationIds,
      categoryIds: categoryIds ?? this.categoryIds,
      tags: tags ?? this.tags,
      brands: brands ?? this.brands,
      stockState: stockState ?? this.stockState,
      expiry: expiry ?? this.expiry,
    );
  }

  /// Serialises to the shape the API and the assistant's `search_products` share.
  ///
  /// Empty axes are omitted rather than sent as empty lists, so a stored saved
  /// filter stays readable and a query string stays short.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (query.isNotEmpty) 'query': query,
      if (locationIds.isNotEmpty) 'location_ids': locationIds.toList(),
      if (categoryIds.isNotEmpty) 'category_ids': categoryIds.toList(),
      if (tags.isNotEmpty) 'tags': tags.toList(),
      if (brands.isNotEmpty) 'brands': brands.toList(),
      if (stockState != StockStateFilter.any) 'stock_state': stockState.name,
      if (expiry != ExpiryFilter.any) 'expiry': expiry.name,
    };
  }

  /// Rebuilds a filter from [toMap]'s output.
  ///
  /// An unrecognised enum value falls back to `any` rather than throwing: a saved
  /// filter is user data that outlives a release, and a renamed option should
  /// widen the filter rather than break the screen that loads it.
  factory ProductFilter.fromMap(Map<String, Object?> map) {
    Set<String> setOf(String key) {
      final Object? raw = map[key];
      return raw is List ? raw.map((e) => e.toString()).toSet() : const <String>{};
    }

    return ProductFilter(
      query: map['query']?.toString() ?? '',
      locationIds: setOf('location_ids'),
      categoryIds: setOf('category_ids'),
      tags: setOf('tags'),
      brands: setOf('brands'),
      stockState: StockStateFilter.values.firstWhere(
        (s) => s.name == map['stock_state'],
        orElse: () => StockStateFilter.any,
      ),
      expiry: ExpiryFilter.values.firstWhere(
        (e) => e.name == map['expiry'],
        orElse: () => ExpiryFilter.any,
      ),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ProductFilter &&
        other.query == query &&
        setEquals(other.locationIds, locationIds) &&
        setEquals(other.categoryIds, categoryIds) &&
        setEquals(other.tags, tags) &&
        setEquals(other.brands, brands) &&
        other.stockState == stockState &&
        other.expiry == expiry;
  }

  @override
  int get hashCode => Object.hash(
    query,
    Object.hashAllUnordered(locationIds),
    Object.hashAllUnordered(categoryIds),
    Object.hashAllUnordered(tags),
    Object.hashAllUnordered(brands),
    stockState,
    expiry,
  );
}

/// A named [ProductFilter] the user can reapply with one tap.
///
/// **It stores criteria, not results.** The documented failure of this pattern is
/// a saved filter that freezes the rows matching it at save time, so tomorrow's
/// newly expiring product never shows up under "Yakında bitecek" and the user
/// quietly stops trusting the list. Holding a [ProductFilter] makes it a live
/// query by construction.
@immutable
class SavedProductFilter {
  /// Stable id. The built-ins use a `builtin:` prefix so they cannot collide with
  /// a server-assigned uuid.
  final String id;

  /// The user-visible name, shown on the chip.
  final String name;

  /// The criteria to apply.
  final ProductFilter filter;

  /// Whether this ships with the app rather than being created by the user.
  ///
  /// Built-ins are not deletable and not editable: they are the reason filtering
  /// has any value before the user has built anything.
  final bool isBuiltIn;

  /// Creates a [SavedProductFilter].
  const SavedProductFilter({
    required this.id,
    required this.name,
    required this.filter,
    this.isBuiltIn = false,
  });

  /// The filters that ship with the app.
  ///
  /// They overlap the list's own "Dikkat gerekiyor" section deliberately: that
  /// section is the always-visible summary of the same conditions, and these are
  /// the drill-in that shows one of them complete rather than truncated.
  /// A getter rather than a `const` list, and the reason is a defect this shape caused.
  ///
  /// The names were const Turkish literals, which was invisible while the whole interface was
  /// Turkish and became three Turkish chips on an English screen the moment the default locale
  /// moved to `en` (D116). `Lang.get` cannot be called from a const expression, so the list is
  /// built per read, which also means a language change takes effect without a restart. Three
  /// objects per read is nothing next to the row list this filters.
  static List<SavedProductFilter> get builtIns => <SavedProductFilter>[
    SavedProductFilter(
      id: 'builtin:expired',
      name: Lang.get('screens.products.saved.expired'),
      filter: const ProductFilter(expiry: ExpiryFilter.expired),
      isBuiltIn: true,
    ),
    SavedProductFilter(
      id: 'builtin:expiring',
      name: Lang.get('screens.products.saved.expiring'),
      filter: const ProductFilter(expiry: ExpiryFilter.expiringSoon),
      isBuiltIn: true,
    ),
    SavedProductFilter(
      id: 'builtin:out-of-stock',
      name: Lang.get('screens.products.saved.out_of_stock'),
      filter: const ProductFilter(stockState: StockStateFilter.outOfStock),
      isBuiltIn: true,
    ),
  ];
}
