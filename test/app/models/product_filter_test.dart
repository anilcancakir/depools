import 'package:depools/app/models/product_filter.dart';
import 'package:depools/resources/views/products/product_fixtures.dart';
import 'package:flutter_test/flutter_test.dart';

/// The filter is the only logic on the stock list screen, and it is what decides
/// which of a tenant's products they can see. So these tests cover the decisions
/// that are easy to get quietly wrong: what counts as empty, what "below par" means
/// when no target is set, whether an expired product is also "expiring soon", and
/// whether removing one criterion leaves the others alone.
void main() {
  group('ProductFilter.isEmpty', () {
    test('a fresh filter is empty', () {
      expect(const ProductFilter().isEmpty, isTrue);
    });

    test('a changed expiry horizon alone is still empty', () {
      // The horizon is the parameter of a constraint, not a constraint. If this
      // regressed, the bar would show an "applied" row with no criteria in it.
      expect(const ProductFilter(expiringWithinDays: 30).isEmpty, isTrue);
    });

    test('any single axis makes it active', () {
      expect(const ProductFilter(query: 'süt').isActive, isTrue);
      expect(const ProductFilter(tags: {'kahvaltı'}).isActive, isTrue);
      expect(const ProductFilter(stockState: StockStateFilter.outOfStock).isActive, isTrue);
    });
  });

  group('ProductFilter.criteria', () {
    test('removing one criterion keeps the others', () {
      const filter = ProductFilter(
        query: 'süt',
        stockState: StockStateFilter.outOfStock,
        tags: {'kahvaltı', 'soğuk zincir'},
      );

      final query = filter.criteria().firstWhere((c) => c.label == '"süt"');

      expect(query.remainder.query, isEmpty);
      expect(query.remainder.stockState, StockStateFilter.outOfStock);
      expect(query.remainder.tags, {'kahvaltı', 'soğuk zincir'});
    });

    test('removing one value of a multi-select leaves its siblings', () {
      const filter = ProductFilter(tags: {'kahvaltı', 'bakliyat'});

      final one = filter.criteria().firstWhere((c) => c.label == 'kahvaltı');

      expect(one.remainder.tags, {'bakliyat'});
    });

    test('an unresolvable id is dropped rather than shown as a blank chip', () {
      const filter = ProductFilter(locationIds: {'loc-deleted'});

      final labels = filter.criteria(resolveLocation: (_) => null).map((c) => c.label);

      expect(labels, isEmpty);
    });

    test('coarse constraints are listed before the multi-selects', () {
      const filter = ProductFilter(
        query: 'süt',
        stockState: StockStateFilter.belowPar,
        tags: {'kahvaltı'},
      );

      expect(
        filter.criteria().map((c) => c.label),
        ['"süt"', 'Az kalan', 'kahvaltı'],
      );
    });
  });

  group('ProductFilter serialisation', () {
    test('a round trip preserves every axis', () {
      const filter = ProductFilter(
        query: 'süt',
        locationIds: {'loc-fridge'},
        categoryIds: {'cat-dairy'},
        tags: {'kahvaltı'},
        brands: {'Pınar'},
        stockState: StockStateFilter.belowPar,
        expiry: ExpiryFilter.expiringSoon,
        expiringWithinDays: 14,
      );

      expect(ProductFilter.fromMap(filter.toMap()), filter);
    });

    test('empty axes are omitted from the map', () {
      expect(const ProductFilter().toMap(), isEmpty);
    });

    test('an unknown enum value widens rather than throwing', () {
      // A saved filter is user data that outlives a release. A renamed option should
      // drop the constraint, not break the screen that loads it.
      final filter = ProductFilter.fromMap({'stock_state': 'someRemovedOption'});

      expect(filter.stockState, StockStateFilter.any);
    });
  });

  group('ProductListItem.matches', () {
    ProductListItem itemNamed(String name) =>
        productFixtures.firstWhere((i) => i.name.startsWith(name));

    test('an empty filter matches everything', () {
      expect(
        productFixtures.where((i) => i.matches(const ProductFilter())).length,
        productFixtures.length,
      );
    });

    test('free text is case-insensitive over name and brand', () {
      expect(itemNamed('Pınar').matches(const ProductFilter(query: 'pınar süt')), isTrue);
      expect(itemNamed('Yoğurt').matches(const ProductFilter(query: 'sütaş')), isTrue);
      expect(itemNamed('Un').matches(const ProductFilter(query: 'süt')), isFalse);
    });

    test('a product in any selected location matches', () {
      // Pınar Süt is in two locations. Selecting either one has to find it.
      expect(
        itemNamed('Pınar').matches(const ProductFilter(locationIds: {'loc-pantry'})),
        isTrue,
      );
      expect(
        itemNamed('Pınar').matches(const ProductFilter(locationIds: {'loc-freezer'})),
        isFalse,
      );
    });

    test('below par needs a target that the user actually set', () {
      // Ayçiçek Yağı has stock and no par level. Without the null guard it would
      // report as running low, and every product without a target would too.
      const belowPar = ProductFilter(stockState: StockStateFilter.belowPar);

      expect(itemNamed('Ayçiçek').parLevel, isNull);
      expect(itemNamed('Ayçiçek').matches(belowPar), isFalse);
      expect(itemNamed('Pınar').matches(belowPar), isTrue); // 5 of a target of 6
    });

    test('out of stock is not below par', () {
      // Kıyma is at zero. It belongs to "Stok yok", and reporting it under "Az
      // kalan" as well would double-count it in two mutually exclusive segments.
      expect(
        itemNamed('Kıyma').matches(const ProductFilter(stockState: StockStateFilter.belowPar)),
        isFalse,
      );
      expect(
        itemNamed('Kıyma').matches(const ProductFilter(stockState: StockStateFilter.outOfStock)),
        isTrue,
      );
    });

    test('an expired product is not "expiring soon"', () {
      // Pınar Süt went off yesterday. Folding it into the horizon would make
      // "7 gün içinde bitecek" include things that expired last month.
      expect(
        itemNamed('Pınar').matches(const ProductFilter(expiry: ExpiryFilter.expired)),
        isTrue,
      );
      expect(
        itemNamed('Pınar').matches(const ProductFilter(expiry: ExpiryFilter.expiringSoon)),
        isFalse,
      );
    });

    test('the horizon is respected on both sides', () {
      // Yoğurt has 9 days left: inside 14, outside 7.
      expect(
        itemNamed('Yoğurt').matches(
          const ProductFilter(expiry: ExpiryFilter.expiringSoon, expiringWithinDays: 14),
        ),
        isTrue,
      );
      expect(
        itemNamed('Yoğurt').matches(
          const ProductFilter(expiry: ExpiryFilter.expiringSoon, expiringWithinDays: 7),
        ),
        isFalse,
      );
    });

    test('a product that tracks no expiry never matches an expiry constraint', () {
      expect(itemNamed('Un').daysUntilExpiry, isNull);
      expect(itemNamed('Un').matches(const ProductFilter(expiry: ExpiryFilter.expired)), isFalse);
      expect(
        itemNamed('Un').matches(const ProductFilter(expiry: ExpiryFilter.expiringSoon)),
        isFalse,
      );
    });

    test('axes combine as AND', () {
      // Kıyma is out of stock but in the freezer, so pairing the fridge with
      // out-of-stock has to match nothing. This is the case the screen's
      // "no matches" state exists for.
      const filter = ProductFilter(
        stockState: StockStateFilter.outOfStock,
        locationIds: {'loc-fridge'},
      );

      expect(productFixtures.where((i) => i.matches(filter)), isEmpty);
    });
  });

  group('the built-in saved filters', () {
    test('each one matches something in the fixtures', () {
      // A built-in that matches nothing on a realistic catalogue is a chip the user
      // taps once and never trusts again.
      for (final SavedProductFilter saved in SavedProductFilter.builtIns) {
        expect(
          productFixtures.where((i) => i.matches(saved.filter)),
          isNotEmpty,
          reason: '${saved.name} matched no fixture',
        );
      }
    });

    test('they are live queries, not frozen results', () {
      // The documented failure of this pattern is a saved filter that stores the
      // rows matching it at save time. Re-evaluating against a different catalogue
      // has to give a different answer.
      final expired = SavedProductFilter.builtIns.firstWhere((s) => s.id == 'builtin:expired');

      const fresh = ProductListItem(
        name: 'Yeni ürün',
        amount: 1,
        formatted: '1',
        unit: 'adet',
        daysUntilExpiry: 30,
      );

      expect(fresh.matches(expired.filter), isFalse);
      expect(productFixtures.any((i) => i.matches(expired.filter)), isTrue);
    });
  });
}
