import 'package:depools/resources/views/products/product_fixtures.dart';
import 'package:depools/resources/views/products/running_low_fixtures.dart';
import 'package:depools/resources/views/products/shopping_fixtures.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('running low', () {
    test('every short product is also on the shopping list', () {
      // The two screens describe the same shortage from different angles, so a product
      // missing from one of them is a contradiction the user would see immediately. This
      // app has already shipped a list and a detail page disagreeing about one product.
      final Set<String> onList = shoppingLines.map((l) => l.name).toSet();
      final List<String> missing = belowTarget
          .map((p) => p.name)
          .where((name) => !onList.contains(name))
          .toList();

      expect(missing, isEmpty, reason: 'below target but absent from the shopping list');
    });

    test('the shopping list is a superset, not an equal', () {
      // Asserting equality would assert something false: the list also carries expiring
      // and manual rows. This locks in the DIRECTION of the containment.
      final Set<String> short = belowTarget.map((p) => p.name).toSet();
      expect(shoppingLines.length, greaterThan(short.length));
    });

    test('the groups partition the short products exactly once each', () {
      final int grouped =
          outOfStock.length + ForecastTier.values.fold(0, (sum, t) => sum + lowInTier(t).length);

      expect(grouped, belowTarget.length);
    });

    test('only the forecast tier carries a days-of-cover figure', () {
      // forecasting.md gates hard here: below ten movements no forecast is shown at all.
      for (final ProductListItem p in productFixtures) {
        if (p.daysOfCover != null) {
          expect(p.tier, ForecastTier.forecast, reason: '${p.name} claims cover without history');
        }
      }
    });
  });
}
