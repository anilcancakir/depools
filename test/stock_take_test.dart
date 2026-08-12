import 'package:depools/resources/views/products/count_fixtures.dart';
import 'package:depools/resources/views/products/count_line.dart';
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

    test('a content declared in the base unit is never split, at any amount', () {
      // The guard checked only `contentAmount > 1`, which caught the demo tenant's `l` holding `1 l`
      // and would have let through the shape it is written for: `g` holding `500 g` passes an amount
      // test and still says a gram contains five hundred grams. Splitting 1.5 of that would print
      // "1 g + 250 g".
      const ProductListItem grams = ProductListItem(
        name: 'Peynir',
        amount: 1.5,
        formatted: '1',
        unit: 'g',
        contentAmount: 500,
        contentUnit: 'g',
      );

      expect(grams.hasFinerContent, isFalse);
      expect(grams.innerFor(1.5), isNull);
      expect(CountLine(product: grams, expected: 1.5).figure(1.5), '1.50 g');

      // A genuinely finer content still splits, which is the case D26 is about.
      const ProductListItem carton = ProductListItem(
        name: 'Süt',
        amount: 1.5,
        formatted: '1',
        unit: 'piece',
        contentAmount: 1000,
        contentUnit: 'ml',
      );

      expect(carton.hasFinerContent, isTrue);
      expect(carton.innerFor(1.5), 500);
      expect(CountLine(product: carton, expected: 1.5).figure(1.5), '1 piece + 500 ml');
    });

    test('a projection that did not travel falls back to the lots', () {
      final ProductListItem milk = productFixtures.firstWhere(
        (p) => p.name == 'Pınar Süt Tam Yağlı 1 lt',
      );

      // A location row carrying no usable quantity is OMITTED from the map rather than stored as 0.
      // The two are different facts and only one of them is a shelf: a defaulted zero would
      // short-circuit `expectedAt` and report an empty shelf for stock the record holds.
      final ProductListItem parsed = ProductListItem.fromApi(
        <String, dynamic>{
          'id': 'p1',
          'name': milk.name,
          'base_unit': 'adet',
          'quantity': '4.000',
          'locations': <Map<String, dynamic>>[
            <String, dynamic>{'location_id': 'loc-a', 'quantity': '3.000'},
            <String, dynamic>{'location_id': 'loc-b', 'quantity': null},
          ],
        },
        locationLabels: const <String, String>{},
      );

      expect(parsed.locationAmounts['loc-a'], 3);
      expect(parsed.locationAmounts.containsKey('loc-b'), isFalse);

      // `loc-b` therefore reaches the fallback rather than reporting a counted-empty shelf. With no
      // lots on this payload that is the product's whole balance, which is the documented limit of
      // the fallback and the reason the first test in this group exists.
      expect(expectedAt(parsed, 'loc-a'), 3);
      expect(expectedAt(parsed, 'loc-b'), 4);
    });

    test('agreement is the same width here as it is on the server', () {
      // `StockWriter::COUNT_EPSILON` is 0.0005. This side was 0.0001, so a difference between the two
      // thresholds read as a variance on the sheet, got submitted, and came back `matched`: the footer
      // promised a movement nobody was going to write.
      expect(CountLine.matchEpsilon, 0.0005);

      final CountLine product = fridgeCount.first;

      // Inside the window on both sides now, where it used to differ.
      expect(
        CountLine(product: product.product, expected: 2, countedWhole: 2.0003).isMatched,
        isTrue,
      );

      // And a difference the column CAN hold is still a difference.
      expect(
        CountLine(product: product.product, expected: 2, countedWhole: 2.001).isMatched,
        isFalse,
      );
    });

    test('a remainder with no whole count is still a count', () {
      // Somebody counting an opened half-carton and no sealed ones fills only the second field. This
      // read `countedWhole != null`, so the row was treated as untouched: left out of the summary,
      // never submitted, and labelled "Not counted" under the number they had just typed.
      final CountLine milk = fridgeCount.first;
      final CountLine remainderOnly = CountLine(
        product: milk.product,
        expected: 2,
        countedRemainder: 500,
      );

      expect(remainderOnly.isCounted, isTrue);
      expect(remainderOnly.countedTotal, 0.5, reason: 'no cartons plus 500 of 1000 ml');
      expect(remainderOnly.variance, -1.5);

      // And an untouched row is still untouched: BOTH fields empty is the uncounted case (D58).
      const CountLine neither = CountLine(product: ProductListItem(
        name: 'x',
        amount: 0,
        formatted: '0',
        unit: 'adet',
      ), expected: 2);

      expect(neither.isCounted, isFalse);
      expect(neither.countedTotal, isNull);
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
    });

    test('a base unit that is its own content unit states a decimal', () {
      // The demo tenant's milk: base unit `l`, content `1 l`. The whole-plus-remainder split needs a
      // FINER inner unit to mean anything, and with content 1 the inner amount is the same decimal,
      // so the formatter rounded it to a whole and printed 7.5 l as "7 l + 1 l" - which reads as 8.
      const ProductListItem litres = ProductListItem(
        name: 'Whole Milk 1 L',
        amount: 7.5,
        formatted: '7',
        unit: 'l',
        contentAmount: 1,
        contentUnit: 'l',
      );

      final CountLine line = CountLine(product: litres, expected: 7.5, countedWhole: 8);

      expect(line.hasFinerContent, isFalse);
      expect(line.figure(7.5), '7.50 l');
      expect(line.figure(0.5), '0.50 l');
      expect(line.figure(8), '8 l');

      // The carton case still splits, which is what D26 is about.
      expect(fridgeCount.first.hasFinerContent, isTrue);
      expect(fridgeCount.first.figure(1.5), '1 adet + 500 ml');
    });

    test('the verdict names the direction the shelf disagrees in', () {
      // **`Lang.get` returns the KEY in a test**, because nothing loads the catalogue here, and
      // `dashboard_first_run_test` records the same fact. So what is observable is the BRANCH, which
      // is the only part this class decides: the figures it interpolates are asserted through
      // `figure` above, and `localization_test` asserts the placeholders survive translation.
      //
      // This used to assert the whole Turkish sentence, which passed for as long as the sentence was
      // hardcoded Turkish and no English user could ever see it.
      final CountLine milk = fridgeCount.first;
      expect(milk.variance, -0.5);
      expect(milk.verdict, 'screens.stock_take.verdict_short');

      expect(
        CountLine(product: milk.product, expected: 1, countedWhole: 3).verdict,
        'screens.stock_take.verdict_over',
      );
      expect(
        CountLine(product: milk.product, expected: 2, countedWhole: 2).verdict,
        'screens.stock_take.verdict_matched',
      );
      expect(
        CountLine(product: milk.product, expected: 2).verdict,
        'screens.stock_take.verdict_uncounted',
      );
    });

    test('the expected figure prefers the projection over the lots', () {
      // On real data the list endpoint sends `product_stock` per location and never sends lots, so
      // this is the ONLY source that exists there. A fixture has it the other way round, and the
      // fallback is what keeps the preview renderable.
      final ProductListItem milk = productFixtures.firstWhere(
        (p) => p.name == 'Pınar Süt Tam Yağlı 1 lt',
      );

      expect(milk.locationAmounts, isEmpty, reason: 'a fixture carries no projection');
      expect(expectedAt(milk, 'loc-fridge'), milk.amountAt('loc-fridge'));

      // The same product with a projection that DISAGREES with its lots. The projection wins, which
      // is the behaviour that matters: a stale client-side lot sum must not decide what gets written.
      final ProductListItem projected = ProductListItem(
        name: milk.name,
        amount: milk.amount,
        formatted: milk.formatted,
        unit: milk.unit,
        lots: milk.lots,
        locationIds: milk.locationIds,
        locationAmounts: const <String, num>{'loc-fridge': 9},
      );

      expect(expectedAt(projected, 'loc-fridge'), 9);
    });

    test('a commit separates what landed from what the user still has to finish', () {
      const CountCommit commit = CountCommit.landed(<CountResult>[
        CountResult(productId: 'a', outcome: CountOutcome.written, delta: -1),
        CountResult(productId: 'b', outcome: CountOutcome.matched, delta: 0),
        CountResult(productId: 'c', outcome: CountOutcome.needsDate, delta: 2),
        CountResult(productId: 'd', outcome: CountOutcome.serialTracked, delta: 0),
      ]);

      // A matched row is finished and writes nothing, which is exactly why an empty movement list
      // cannot be the signal: it is the same for three of the four outcomes.
      expect(commit.writtenCount, 1);
      expect(commit.unfinished.map((r) => r.productId), <String>['c', 'd']);
      expect(commit.error, isNull);

      const CountCommit failed = CountCommit.failed('nope');
      expect(failed.lines, isEmpty);
      expect(failed.unfinished, isEmpty);
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
