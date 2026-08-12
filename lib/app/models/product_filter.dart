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
  /// **These were const Turkish literals and no gate could see them.**
  /// `no_hardcoded_copy_test` scans `lib/resources/views` and `lib/ui/components`, and this file is in
  /// `lib/app/models`, so the filter sheet showed `Tümü` and `Az kalan` on an English interface for as
  /// long as nobody opened it. The chip names above went through `Lang.get` already, which is what
  /// made the leak so easy to miss: the chips read English and the sheet behind them did not.
  static String stockStateLabel(StockStateFilter state) => switch (state) {
    StockStateFilter.any => Lang.get('screens.product_filter.state_any'),
    StockStateFilter.outOfStock => Lang.get('screens.product_filter.state_out_of_stock'),
    StockStateFilter.belowPar => Lang.get('screens.product_filter.state_below_par'),
    StockStateFilter.inStock => Lang.get('screens.product_filter.state_in_stock'),
  };

  /// The already-localised label for an expiry constraint, as a removable chip.
  ///
  /// Says the whole thing, because a chip has to stand alone: read out of context in
  /// a row of criteria, "Yakında" could be almost anything.
  static String expiryLabel(ExpiryFilter expiry) => switch (expiry) {
    ExpiryFilter.any => Lang.get('screens.product_filter.expiry_any'),
    ExpiryFilter.expired => Lang.get('screens.product_filter.expiry_expired'),
    ExpiryFilter.expiringSoon => Lang.get('screens.product_filter.expiry_expiring_soon'),
  };

  /// The same constraint, shortened for a segmented control.
  ///
  /// The group label ("Son kullanma") already supplies what the chip has to spell
  /// out, so the segment can drop the verb and fit three options on a phone.
  static String expirySegmentLabel(ExpiryFilter expiry) => switch (expiry) {
    ExpiryFilter.any => Lang.get('screens.product_filter.expiry_any'),
    ExpiryFilter.expired => Lang.get('screens.product_filter.expiry_segment_expired'),
    ExpiryFilter.expiringSoon => Lang.get('screens.product_filter.expiry_segment_expiring_soon'),
  };

  /// Returns a copy with the given fields replaced.
  /// This filter with [other]'s constraints laid over it.
  ///
  /// **What a quick-filter chip does when one is already applied.** The chips used to disappear the
  /// moment anything was in force, so switching from "Expired" to "Low stock" cost a tap to clear, a
  /// moment with the list unfiltered, and a second tap. Anılcan pointed at the X on an applied chip
  /// and read it as a promise of multi-select, correctly.
  ///
  /// Merging is what makes that promise keepable where the model can keep it. Measured against the
  /// demo tenant: of the six pairs the four built-ins can form, TWO match products (expired plus low
  /// stock, 3 rows; expiring soon plus low stock, 3), two are empty by construction (an out-of-stock
  /// product has no lots, so it has no date to be expired by), and two are impossible because their
  /// axis holds one value. Free multi-select would have offered all six and four of them could never
  /// match anything, which is the same shape as a filter that lies.
  ///
  /// So a same-axis chip REPLACES rather than combining, which is the only thing a single-valued axis
  /// can mean, and a cross-axis one narrows. The set axes union, because a second location is another
  /// place to look rather than a contradiction.
  ///
  /// An empty axis on [other] is not a constraint and leaves this one alone: that is what lets a chip
  /// carry exactly its own criterion.
  ProductFilter mergedWith(ProductFilter other) {
    return ProductFilter(
      query: other.query.isEmpty ? query : other.query,
      locationIds: {...locationIds, ...other.locationIds},
      categoryIds: {...categoryIds, ...other.categoryIds},
      tags: {...tags, ...other.tags},
      brands: {...brands, ...other.brands},
      stockState: other.stockState == StockStateFilter.any ? stockState : other.stockState,
      expiry: other.expiry == ExpiryFilter.any ? expiry : other.expiry,
    );
  }

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

  /// The wire spelling of each stock state.
  ///
  /// **`snake_case`, not the Dart enum's own `name`.** `stockState.name` gives `outOfStock`, and the
  /// rest of this API speaks snake_case: the count endpoint already answers `needs_date` and
  /// `serial_tracked`. One vocabulary in two casings inside one contract is a thing to look up rather
  /// than a thing to know, and `ProductListQuery` validates against exactly these strings.
  ///
  /// `any` is absent on purpose. An unconstrained axis is not a criterion, so it is omitted from the
  /// payload rather than sent as a value meaning "no".
  static const Map<StockStateFilter, String> _stockStateWire = <StockStateFilter, String>{
    StockStateFilter.outOfStock: 'out_of_stock',
    StockStateFilter.belowPar: 'below_par',
    StockStateFilter.inStock: 'in_stock',
  };

  /// The wire spelling of each expiry constraint. See [_stockStateWire].
  static const Map<ExpiryFilter, String> _expiryWire = <ExpiryFilter, String>{
    ExpiryFilter.expired: 'expired',
    ExpiryFilter.expiringSoon: 'expiring_soon',
  };

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
      if (stockState != StockStateFilter.any) 'stock_state': _stockStateWire[stockState],
      if (expiry != ExpiryFilter.any) 'expiry': _expiryWire[expiry],
    };
  }

  /// [toMap] as a URL query string, plus whatever else the caller is sending.
  ///
  /// **A list becomes `key[]=a&key[]=b`, and that suffix is the whole reason this exists.** Dio
  /// encodes a `List` as `key=a&key=b` by default, and PHP's parser keeps only the LAST value for a
  /// repeated bare key: three selected shelves would arrive as one, and the list would come back
  /// narrower than the chips say it is. Nothing errors, which is what makes it worth a named method
  /// with a test rather than an inline join at the call site.
  ///
  /// Lives here rather than in the controller because the encoding is a property of this shared wire
  /// shape; [extra] is where the transport's own concerns (the cursor, the page size) go, so the
  /// filter does not have to know about them.
  String toQueryString({Map<String, Object?> extra = const <String, Object?>{}}) {
    final List<String> pairs = <String>[];

    void add(String key, Object? value) {
      if (value == null) return;

      pairs.add(
        '${Uri.encodeQueryComponent(key)}=${Uri.encodeQueryComponent(value.toString())}',
      );
    }

    for (final MapEntry<String, Object?> entry in <String, Object?>{...toMap(), ...extra}.entries) {
      final Object? value = entry.value;

      if (value is List) {
        for (final Object? item in value) {
          add('${entry.key}[]', item);
        }
      } else {
        add(entry.key, value);
      }
    }

    return pairs.join('&');
  }

  /// Rebuilds a filter from a URL's query parameters.
  ///
  /// **The URL carries the same shape as the API request, deliberately.** [toQueryString] writes
  /// `location_ids[]=a&location_ids[]=b`, and this reads exactly that back, so a filter has ONE wire
  /// encoding rather than one for the server and a prettier one for the address bar. A second
  /// spelling would be a second parser, and the two would drift on the first axis somebody added.
  ///
  /// Takes `queryParametersAll` and not `queryParameters`: the collapsed map keeps only the LAST
  /// value for a repeated key, so three selected shelves would come back as one and the list would
  /// silently be wider than the URL said.
  ///
  /// An unknown value falls back to `any`, like [fromMap], because a shared link outlives the
  /// release that wrote it and a renamed option should widen the filter rather than break the screen.
  factory ProductFilter.fromQueryParameters(Map<String, List<String>> params) {
    Set<String> setOf(String key) =>
        (params['$key[]'] ?? params[key] ?? const <String>[]).where((v) => v.isNotEmpty).toSet();

    String? first(String key) {
      final List<String>? values = params[key];

      return values == null || values.isEmpty ? null : values.first;
    }

    return ProductFilter(
      query: first('query') ?? '',
      locationIds: setOf('location_ids'),
      categoryIds: setOf('category_ids'),
      tags: setOf('tags'),
      brands: setOf('brands'),
      stockState: StockStateFilter.values.firstWhere(
        (s) => _stockStateWire[s] == first('stock_state'),
        orElse: () => StockStateFilter.any,
      ),
      expiry: ExpiryFilter.values.firstWhere(
        (e) => _expiryWire[e] == first('expiry'),
        orElse: () => ExpiryFilter.any,
      ),
    );
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
        (s) => _stockStateWire[s] == map['stock_state'],
        orElse: () => StockStateFilter.any,
      ),
      expiry: ExpiryFilter.values.firstWhere(
        (e) => _expiryWire[e] == map['expiry'],
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
  /// **They are now the only surface for these conditions.** The list used to carry a separate "needs
  /// attention" section holding the union of them, and it was removed: it split one collection into
  /// two cards, and pushed the catalogue below the fold when open or read as an empty screen when
  /// closed and a filter matched only attention rows. These four chips do the same job in one tap
  /// each, and they show one condition COMPLETE rather than the union truncated.
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
    // **The fourth, and the one that was missing.** These four are the whole set because each maps to
    // a DIFFERENT action, which is the test a quick filter has to pass: out of stock means buy it now,
    // below target means add it to the shopping list, expiring soon means use it up, and expired means
    // write it off. A fifth would either repeat one of those or answer a question nobody asks
    // standing at a shelf.
    //
    // Below-target is the canonical inventory filter and it was the gap: the other three are all
    // about a date or a zero, and none of them answers "what do I need to order", which is the
    // question a reorder point exists for. An unset target can never match, which is deliberate:
    // `isBelowPar` requires a level the user chose, or every product with a little stock would report
    // as low.
    SavedProductFilter(
      id: 'builtin:low-stock',
      name: Lang.get('screens.products.saved.low_stock'),
      filter: const ProductFilter(stockState: StockStateFilter.belowPar),
      isBuiltIn: true,
    ),
  ];
}
