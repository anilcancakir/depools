import 'package:depools/resources/views/products/count_fixtures.dart';
import 'package:depools/resources/views/products/product_fixtures.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('stock take', () {
    test('a lot-less product sits in exactly one location', () {
      // `expectedAt` falls back to the product's whole balance when it has no lots, which is
      // only correct while this holds. Two locations without lots to split them would report
      // the entire balance in both places, and the count screen would invent stock.
      for (final ProductListItem p in productFixtures) {
        if (p.lots.isEmpty) {
          expect(
            p.locationIds.length,
            lessThanOrEqualTo(1),
            reason: '${p.name} has no lots but ${p.locationIds.length} locations',
          );
        }
      }
    });

    test('uncounted is not zero', () {
      final CountLine skipped = fridgeCount.firstWhere((l) => !l.isCounted);
      expect(skipped.countedTotal, isNull);
      expect(skipped.variance, isNull, reason: 'an uncounted line has no difference to write');
    });

    test('the two count fields combine into the base unit', () {
      // The milk holds 1 sealed carton plus 500 ml of a 1000 ml one, so 1.5 in the base unit.
      // Counting 1 and 0 is a variance of exactly minus half a carton.
      final CountLine milk = fridgeCount.first;
      expect(milk.expected, 1.5);
      expect(milk.countedTotal, 1);
      expect(milk.variance, -0.5);
      expect(milk.isMatched, isFalse);
    });

    test('a zero whole is dropped when there is a remainder', () {
      // The hand-written component preview said "500 ml eksik" and the generated verdict
      // said "0 adet + 500 ml eksik". The preview was right, which is why this is a test.
      final CountLine milk = fridgeCount.first;
      expect(milk.figure(0.5), '500 ml');
      expect(milk.figure(1.5), '1 adet + 500 ml');
      expect(milk.figure(2), '2 adet');
      expect(milk.verdict, 'Sistemde 1 adet + 500 ml · 500 ml eksik');
    });

    test('only variances write movements', () {
      expect(countedLines.length, 2);
      expect(varianceLines.length, 1);
      expect(skippedLines.length, 1);
      for (final CountLine line in varianceLines) {
        expect(line.variance, isNot(0));
      }
    });
  });
}
