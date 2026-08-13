import 'package:flutter_test/flutter_test.dart';

import 'package:depools/app/support/scan_outcome.dart';
import 'package:depools/resources/views/products/product_fixtures.dart' show ProductListItem;

/// What a barcode read means for the shelf being counted.
///
/// **This is the only part of scanning that can be checked without a camera, which is why it is a
/// pure function rather than a branch inside the scanner widget.** A headless browser has no camera
/// and Chrome's fake device produces a rolling pattern rather than a barcode, so a design that
/// classified the read where it was captured would leave all three answers verifiable only by hand
/// on a device.
void main() {
  ProductListItem productAt(Set<String> locationIds) => ProductListItem(
    id: 'p1',
    name: 'Whole Milk 1 L',
    locationIds: locationIds,
    locationSummary: '',
    tags: const <String>{},
    amount: 3,
    formatted: '3',
    unit: 'piece',
  );

  test('a product the record puts on this shelf is counted', () {
    final ScanOutcome outcome = ScanOutcome.of(
      code: '8690504010012',
      product: productAt(<String>{'loc-fridge', 'loc-pantry'}),
      shelfId: 'loc-fridge',
    );

    expect(outcome.verdict, ScanVerdict.onShelf);
    expect(outcome.product?.name, 'Whole Milk 1 L');
  });

  test('a product the record puts somewhere else is asked about, not counted', () {
    // Counting it here silently would move stock with a gesture that looks like a count, which is
    // the one thing a ledger cannot take back without a compensating movement.
    final ScanOutcome outcome = ScanOutcome.of(
      code: '8690504010012',
      product: productAt(<String>{'loc-pantry'}),
      shelfId: 'loc-fridge',
    );

    expect(outcome.verdict, ScanVerdict.elsewhere);
    expect(outcome.product, isNotNull);
  });

  test('a product holding nothing anywhere is elsewhere rather than here', () {
    // **The empty set is the case that decides the rule's shape.** A shelf's count list holds what
    // the record says is on it, so a product with no stock at all is not on this one. Treating an
    // empty set as "no evidence against" would count inbound stock as a count, which is a different
    // movement with a different reason and needs a date this screen never asks for.
    final ScanOutcome outcome = ScanOutcome.of(
      code: '8690504010012',
      product: productAt(const <String>{}),
      shelfId: 'loc-fridge',
    );

    expect(outcome.verdict, ScanVerdict.elsewhere);
  });

  test('a code nothing carries is collected rather than counted', () {
    final ScanOutcome outcome = ScanOutcome.of(
      code: '5060337502900',
      product: null,
      shelfId: 'loc-fridge',
    );

    expect(outcome.verdict, ScanVerdict.unknown);
    expect(outcome.product, isNull);
  });

  test('the code is kept exactly as it was read', () {
    // What the user has to recognise is the number printed under the label they are holding, not the
    // canonical fourteen-digit form the server matched it by.
    const String asPrinted = '869 0504 010012';

    expect(
      ScanOutcome.of(code: asPrinted, product: null, shelfId: 'loc-fridge').code,
      asPrinted,
    );
  });
}
