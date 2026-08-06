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

    test('the expiry axis alone makes it active', () {
      expect(const ProductFilter(expiry: ExpiryFilter.expiringSoon).isActive, isTrue);
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

      expect(filter.criteria().map((c) => c.label), ['"süt"', 'Az kalan', 'kahvaltı']);
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
      expect(itemNamed('Pınar').matches(const ProductFilter(locationIds: {'loc-pantry'})), isTrue);
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
      expect(itemNamed('Pınar').matches(const ProductFilter(expiry: ExpiryFilter.expired)), isTrue);
      expect(
        itemNamed('Pınar').matches(const ProductFilter(expiry: ExpiryFilter.expiringSoon)),
        isFalse,
      );
    });

    test('the window is derived from each product\'s own shelf life', () {
      // This is the whole reason the fixed horizon went away. Yoğurt has 9 days left
      // on a 21 day shelf life, so its window is 4 days and 9 days out is NOT a
      // warning. The same 9 days on a 5 day carton of milk would be, several times
      // over. One global number cannot express both.
      const soon = ProductFilter(expiry: ExpiryFilter.expiringSoon);

      expect(itemNamed('Yoğurt').expiryThresholdDays, 4);
      expect(itemNamed('Yoğurt').matches(soon), isFalse);

      expect(itemNamed('Pınar').expiryThresholdDays, 1);
      expect(itemNamed('Bulgur').expiryThresholdDays, 60); // 365 days, hits the cap
      expect(itemNamed('Bulgur').matches(soon), isTrue); // 2 days left, well inside
    });

    test('the window is floored at a day and capped at two months', () {
      // A one-day-shelf-life item must still get a window, and a ten year item must
      // not start warning three years out.
      const fresh = ProductListItem(
        name: 'Taze',
        amount: 1,
        formatted: '1',
        unit: 'adet',
        shelfLifeDays: 1,
      );
      const forever = ProductListItem(
        name: 'Konserve',
        amount: 1,
        formatted: '1',
        unit: 'adet',
        shelfLifeDays: 3650,
      );

      expect(fresh.expiryThresholdDays, 1);
      expect(forever.expiryThresholdDays, ProductListItem.maxThresholdDays);
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
