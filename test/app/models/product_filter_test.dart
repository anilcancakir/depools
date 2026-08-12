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

    test('merging a quick filter narrows across axes and replaces within one', () {
      // What a chip does when one is already applied. Measured against the demo tenant: of the six
      // pairs the four built-ins can form, two match rows (expired + low stock, expiring + low
      // stock), two are empty by construction because an out-of-stock product has no lots and so no
      // date, and two are impossible because their axis holds a single value.
      const expired = ProductFilter(expiry: ExpiryFilter.expired);
      const lowStock = ProductFilter(stockState: StockStateFilter.belowPar);
      const outOfStock = ProductFilter(stockState: StockStateFilter.outOfStock);

      // Cross-axis: both survive, which is the pair with rows behind it.
      final both = expired.mergedWith(lowStock);
      expect(both.expiry, ExpiryFilter.expired);
      expect(both.stockState, StockStateFilter.belowPar);

      // Same axis: the newer value wins, because that is the only thing one slot can mean.
      final replaced = lowStock.mergedWith(outOfStock);
      expect(replaced.stockState, StockStateFilter.outOfStock);

      // An empty axis is not a constraint, so merging a chip carries exactly its own criterion and
      // leaves a search term and a tag set alone.
      const narrowed = ProductFilter(query: 'süt', tags: {'kahvaltı'});
      final merged = narrowed.mergedWith(lowStock);
      expect(merged.query, 'süt');
      expect(merged.tags, {'kahvaltı'});
      expect(merged.stockState, StockStateFilter.belowPar);

      // And merging something already in force is a no-op, which is what hides an inert chip.
      expect(lowStock.mergedWith(lowStock), lowStock);
    });

    test('coarse constraints are listed before the multi-selects', () {
      const filter = ProductFilter(
        query: 'süt',
        stockState: StockStateFilter.belowPar,
        tags: {'kahvaltı'},
      );

      // The stock-state label is a KEY here, not a sentence: `Lang.get` returns the key in a test
      // because nothing loads the catalogue, and this used to assert `'Az kalan'` because the label
      // was a hardcoded Turkish literal. That literal was the defect (the filter sheet read Turkish
      // on an English interface), so the assertion moves to the key and the ORDER, which is what this
      // test is actually about. A search term and a tag are user data and stay verbatim.
      expect(filter.criteria().map((c) => c.label), [
        '"süt"',
        'screens.product_filter.state_below_par',
        'kahvaltı',
      ]);
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

    test('the wire vocabulary is snake_case, which the Dart enum name is not', () {
      // `stockState.name` gives `outOfStock`, and `ProductListQuery` validates against
      // `out_of_stock`. A camelCase value would be REFUSED with a 422 rather than silently
      // ignored, which is the better failure, but it is still a broken filter.
      const filter = ProductFilter(
        stockState: StockStateFilter.outOfStock,
        expiry: ExpiryFilter.expiringSoon,
      );

      expect(filter.toMap()['stock_state'], 'out_of_stock');
      expect(filter.toMap()['expiry'], 'expiring_soon');
    });

    test('a list becomes key[] pairs, because a bare repeated key collapses in PHP', () {
      // **The suffix is the whole content of this test.** Dio encodes a List as `key=a&key=b`, and
      // PHP's parser keeps only the LAST value for a repeated bare key: three selected shelves
      // would arrive as one, and the list would come back narrower than the chips say it is. No
      // error anywhere, on either side.
      const filter = ProductFilter(locationIds: {'a', 'b'});

      final String query = filter.toQueryString();

      expect(query, contains('location_ids%5B%5D=a'));
      expect(query, contains('location_ids%5B%5D=b'));

      // Decoded, the parameter name carries the brackets, which is the form PHP turns into an
      // array. Note what a parser WITHOUT that rule does with the same string: it keeps one value.
      // That is the behaviour on the other side of a bare `location_ids=a&location_ids=b`.
      expect(Uri.splitQueryString(query).keys, <String>['location_ids[]']);
    });

    test('the query string escapes what a user can type, and carries the transport keys', () {
      const filter = ProductFilter(query: 'süt & krema');

      final String query = filter.toQueryString(
        extra: <String, Object?>{'per_page': 30, 'cursor': null},
      );

      // An unescaped `&` would split one term into two parameters, and the second one would be a
      // key the endpoint refuses.
      expect(Uri.splitQueryString(query)['query'], 'süt & krema');
      expect(Uri.splitQueryString(query)['per_page'], '30');

      // A null extra is omitted rather than sent as the string "null", which the cursor validator
      // would accept and the paginator would then fail to decode.
      expect(query, isNot(contains('cursor')));
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
      expect(itemNamed('Pınar').matches(belowPar), isTrue); // 2.5 of a target of 4
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
      // Kaşar went off yesterday. Folding it into the window would make "Yakında
      // bitecek" include things that expired last month.
      expect(itemNamed('Kaşar').matches(const ProductFilter(expiry: ExpiryFilter.expired)), isTrue);
      expect(
        itemNamed('Kaşar').matches(const ProductFilter(expiry: ExpiryFilter.expiringSoon)),
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

    test('the window the API states wins over the local derivation', () {
      // **The server is the authority and the derivation above is the fixture path.** The formula
      // ran in two languages: here for the badge, and in PHP for the "expiring soon" filter. Two
      // implementations is a badge reading "5 days left" in green on a row the filter put under
      // expiring soon, the day either side is tuned. `expiry_threshold_days` is what makes them one.
      final ProductListItem stated = ProductListItem.fromApi(
        <String, dynamic>{
          'id': 'p1',
          'name': 'Konserve',
          'base_unit': 'adet',
          'quantity': '2.000',
          'default_shelf_life_days': 730,
          // Deliberately NOT what the local formula produces for 730 days, which is the cap of 60.
          // A test using the agreeing number could not tell the two sources apart.
          'expiry_threshold_days': 45,
        },
        locationLabels: const <String, String>{},
      );

      expect(stated.expiryThresholdDays, 45);

      // And without it the local derivation still answers, which is what keeps the preview catalog
      // rendering a badge for rows that never went through an endpoint.
      final ProductListItem silent = ProductListItem.fromApi(
        <String, dynamic>{
          'id': 'p2',
          'name': 'Konserve',
          'base_unit': 'adet',
          'quantity': '2.000',
          'default_shelf_life_days': 730,
        },
        locationLabels: const <String, String>{},
      );

      expect(silent.expiryThresholdDays, ProductListItem.maxThresholdDays);
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

  group('the lots are the source of the totals', () {
    ProductListItem itemNamed(String name) =>
        productFixtures.firstWhere((i) => i.name.startsWith(name));

    test('the live lots sum to the declared amount', () {
      // This is the test that would have caught the drift: the detail screen said
      // 5 adet, the list said 2.5, and the lots summed to 4.5. Any of the three
      // changing without the others now fails here rather than on screen.
      for (final ProductListItem item in productFixtures.where((i) => i.lots.isNotEmpty)) {
        final num sum = item.liveLots.fold<num>(0, (a, l) => a + l.remaining);
        expect(
          sum,
          closeTo(item.amount, 0.001),
          reason: '${item.name}: lots sum to \$sum but amount says \${item.amount}',
        );
      }
    });

    test('the locations sum to the total as well', () {
      final milk = itemNamed('Pınar');

      expect(milk.amountAt('loc-fridge'), 1.5); // the open half plus one sealed
      expect(milk.amountAt('loc-pantry'), 1);
      expect(milk.amountAt('loc-fridge') + milk.amountAt('loc-pantry'), milk.amount);
    });

    test('a depleted lot is excluded from the totals but kept', () {
      final milk = itemNamed('Pınar');

      expect(milk.lots.length, 4);
      expect(milk.liveLots.length, 3);
      expect(milk.lots.any((l) => l.isDepleted), isTrue);
    });

    test('the open lot reports the after-opening clock, not the printed date', () {
      // The fixture text says the box reads 12 Ağu while the lot binds in 2 days.
      // If these were ever equal, the whole of D27 would be untested.
      final open = itemNamed('Pınar').lots.firstWhere((l) => l.isOpen);

      expect(open.daysUntilExpiry, 2);
      expect(open.openedLabel, contains('kutuda 12 Ağu'));
      expect(open.unit, 'ml'); // an open lot reports in the content unit
    });
  });

  group('serial tracking', () {
    ProductListItem drill() => productFixtures.firstWhere((p) => p.tracking == TrackingMode.serial);

    test('a serial location reports a whole count, not a lot sum', () {
      // The regression this exists for: summing lots unconditionally reported "0 konum"
      // beside two drills on a shelf, because a serial-tracked product has no lots.
      expect(drill().liveSerials.length, 2);
      expect(drill().amountAt('loc-shelf'), 2);
      expect(drill().amountAt('loc-fridge'), 0);
    });

    test('a unit that has left is excluded from the count but kept', () {
      expect(drill().serials.length, 3);
      expect(drill().serials.any((u) => u.isGone), isTrue);
    });

    test('the declared amount matches the live unit count', () {
      expect(drill().amount, drill().liveSerials.length);
    });

    test('a serial-tracked product declares no lots and no content', () {
      // The two models are mutually exclusive by nature, not by policy: partial
      // consumption (D26) has no meaning for a specific object. Half a drill does not
      // exist, so a fixture carrying both would describe something impossible.
      expect(drill().lots, isEmpty);
      expect(drill().contentAmount, isNull);
      expect(drill().hasOpenUnit, isFalse);
    });

    test('a warranty inside its window puts the product in the attention list', () {
      // Warranty reuses the expiry machinery on purpose, so this needs no separate
      // predicate. A shop that misses a warranty expiry eats the repair.
      expect(drill().needsAttention, isTrue);
      expect(drill().isExpiringSoon, isTrue);
    });
  });

  group('partial quantities', () {
    ProductListItem itemNamed(String name) =>
        productFixtures.firstWhere((i) => i.name.startsWith(name));

    test('whole units lead and the open remainder follows', () {
      // Two sealed cartons plus one open with half a litre: "2 adet + 500 ml".
      final milk = itemNamed('Pınar');

      expect(milk.wholeCount, 2);
      expect(milk.primaryFigure, ('2', 'adet'));
      expect(milk.remainderFigure, ('500', 'ml'));
      expect(milk.openNote, isNull); // "+ 500 ml" already says something is open
    });

    test('when nothing is whole the remainder becomes the primary figure', () {
      // "2 poşet", never "0 paket + 2 poşet". The zero is noise, and worse, Quantity
      // would mute the row as depleted while the user still has something to cook.
      final vanilla = itemNamed('Vanilya');

      expect(vanilla.wholeCount, 0);
      expect(vanilla.primaryFigure, ('2', 'poşet'));
      expect(vanilla.remainderFigure, isNull);
      expect(vanilla.openNote, '1 paket açık');
    });

    test('a product with nothing open renders no remainder at all', () {
      final flour = itemNamed('Un');

      expect(flour.hasOpenUnit, isFalse);
      expect(flour.primaryFigure, ('12,50', 'kg'));
      expect(flour.remainderFigure, isNull);
      expect(flour.openNote, isNull);
    });

    test('an open perishable unit is always in the attention list', () {
      // Two days left on a three-day after-opening clock. The proportional window
      // derived from the PRINTED five-day shelf life is one day, so the proportion
      // alone would keep this silent until its last morning. Being open is the
      // signal, not the arithmetic.
      final milk = itemNamed('Pınar');

      expect(milk.expiryThresholdDays, 1);
      expect(milk.isExpiringSoon, isFalse); // the proportion says no
      expect(milk.isOpenAndPerishable, isTrue);
      expect(milk.needsAttention, isTrue); // and it is listed anyway
    });

    test('an open unit with no after-opening limit is not an event', () {
      // Opening a bag of flour is not news, and it must not park a row in the
      // attention list forever.
      const flour = ProductListItem(
        name: 'Açılmış un',
        amount: 4.5,
        formatted: '4',
        unit: 'kg',
        contentAmount: 1000,
        contentUnit: 'g',
        openRemainder: 500,
      );

      expect(flour.hasOpenUnit, isTrue);
      expect(flour.isOpenAndPerishable, isFalse);
      expect(flour.needsAttention, isFalse);
    });

    test('an open unit still counts as stock on hand', () {
      // 0.67 of a pack is not zero. If this regressed, the vanilla would land in
      // "Stok yok" and the user would be told to buy something they have.
      final vanilla = itemNamed('Vanilya');

      expect(vanilla.amount, greaterThan(0));
      expect(
        vanilla.matches(const ProductFilter(stockState: StockStateFilter.outOfStock)),
        isFalse,
      );
    });
  });
}
