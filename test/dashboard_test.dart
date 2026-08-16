import 'package:depools/resources/views/products/activity_fixtures.dart';
import 'package:depools/resources/views/products/expiring_fixtures.dart';
import 'package:depools/resources/views/products/product_fixtures.dart';
import 'package:depools/resources/views/products/running_low_fixtures.dart';
import 'package:depools/resources/views/products/shopping_fixtures.dart';
import 'package:flutter_test/flutter_test.dart';

/// The dashboard summarises four screens, so every test here asserts that its summary cannot
/// disagree with the screen it links to. None of them assert a literal: a test reading
/// `expect(expiredRows().length, 1)` would pass while the dashboard showed a different number, and
/// would fail on any honest fixture edit.
void main() {
  group('dashboard counters are derived, not restated', () {
    test('the dates card loses no row to its own grouping', () {
      // The dashboard concatenates `expiredRows()` with the FLATTENED `approachingByLocation()`
      // and prints the sum as its count. That grouping walks `locationOptions`, so a lot sitting
      // in a location the option list does not name would vanish from the group map while still
      // counting on the dates screen. The dashboard would then quietly undercount the one thing
      // this app exists to surface.
      final int flattened = approachingByLocation().values.fold(
        0,
        (int sum, List<DatedLot> rows) => sum + rows.length,
      );

      expect(
        expiredRows().length + flattened,
        datedLots().length,
        reason: 'a dated lot is in neither the expired list nor any location group',
      );
    });

    test('expired and approaching do not overlap', () {
      // Both halves come from `datedLots()` and are split on the sign of `daysUntilExpiry`, so an
      // off-by-one at zero would double-count a lot expiring today in the dashboard total.
      final Set<String> expired = expiredRows()
          .map((DatedLot l) => '${l.productName}|${l.label}')
          .toSet();
      final Set<String> approaching = approachingByLocation().values
          .expand((List<DatedLot> rows) => rows)
          .map((DatedLot l) => '${l.productName}|${l.label}')
          .toSet();

      expect(expired.intersection(approaching), isEmpty);
    });

    test('out of stock is contained in below target, so the stock card must de-duplicate', () {
      // The dashboard pulls the out-of-stock rows to the front of `runningLow` rather than
      // appending them, and this is what makes that necessary rather than stylistic. If the
      // containment ever inverts, appending would be correct and the pull would drop rows.
      final Set<String> low = runningLow.map((ProductListItem p) => p.name).toSet();

      for (final ProductListItem p in outOfStock) {
        expect(low, contains(p.name), reason: '${p.name} is out of stock but not below target');
      }
      expect(outOfStock.length, lessThan(runningLow.length));
    });

    test('every source the dashboard reads is non-empty, so no card is dead code', () {
      // Each card is rendered behind an `isNotEmpty` guard. A source that is empty in the fixtures
      // means the card has never been seen, which is how the shelf-photo screen shipped without a
      // preview and how D55's zero-row dates filter survived review.
      expect(productFixtures, isNotEmpty);
      expect(locationOptions, isNotEmpty);
      expect(datedLots(), isNotEmpty);
      expect(runningLow, isNotEmpty);
      expect(pendingLines, isNotEmpty);
      expect(activityEntries, isNotEmpty);
    });

    test('at least one card exceeds the three-row cap, so the footer is exercised', () {
      // The hidden-count footer only appears above the cap. With every collection at three or
      // fewer it would be unreachable code that nobody had rendered.
      final List<int> totals = <int>[
        expiredRows().length + datedLots().where((DatedLot l) => !l.isExpired).length,
        runningLow.length,
        activityEntries.length,
      ];

      expect(totals.any((int t) => t > 3), isTrue);
    });

    test('the calm state is unreachable with these fixtures, and that is deliberate', () {
      // The dashboard renders an empty state when all four counters are zero. It is real code with
      // no fixture behind it, so this test records WHY there is no screenshot of it rather than
      // leaving a future reader to wonder whether the branch is dead.
      final bool calm =
          expiredRows().isEmpty &&
          approachingByLocation().isEmpty &&
          outOfStock.isEmpty &&
          runningLow.isEmpty;

      expect(calm, isFalse, reason: 'the demo tenant is deliberately mid-work, not caught up');
    });
  });
}
