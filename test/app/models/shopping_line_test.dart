import 'package:depools/app/models/shopping_line.dart';
import 'package:depools/ui/components/shopping_row/shopping_row.dart';
import 'package:flutter_test/flutter_test.dart';

/// Decoding `api/v1/shopping`'s wire shape into [ShoppingLine].
///
/// The field vocabulary (and the four reason tiers exercised) mirrors what
/// `lib/resources/views/products/shopping_fixtures.dart` already builds through `ShoppingLine.of`:
/// running-out with a day count, roughly-due with a bucket and no day count, expiring with an opened
/// lot, and a manual line typed by the user with no product behind it. `casts` is empty on this
/// model (see its own docblock: `quantity` needs the app's own decimal read rather than the built-in
/// `double` cast), so there is no cast type to assert here beyond the plain field reads.
void main() {
  group('ShoppingLine.fromApi', () {
    test('a running-out line carries the day count and the product it names', () {
      final ShoppingLine line = ShoppingLine.fromApi(<String, dynamic>{
        'id': 'line-1',
        'product_id': 'p-1',
        'name': 'Pınar Süt Tam Yağlı 1 lt',
        'quantity': 2,
        'unit': 'C62',
        'reason': 'running_out',
        'reason_days': 2,
        'reason_bucket': null,
        'reason_on_hand': 0,
        'reason_lot_is_open': null,
        'reason_target': null,
        'reason_movement_count': 12,
        'checked_at': null,
      });

      expect(line.id, 'line-1');
      expect(line.productId, 'p-1');
      expect(line.name, 'Pınar Süt Tam Yağlı 1 lt');
      expect(line.quantity, 2);
      expect(line.unit, 'C62');
      expect(line.reason, ShoppingReason.runningOut);
      expect(line.days, 2);
      expect(line.movementCount, 12);
      expect(line.isChecked, isFalse);
    });

    test('a roughly-due line carries a bucket and never a day count', () {
      final ShoppingLine line = ShoppingLine.fromApi(<String, dynamic>{
        'id': 'line-2',
        'product_id': 'p-2',
        'name': 'Bulgur',
        'quantity': 1,
        'unit': 'KGM',
        'reason': 'roughly_due',
        'reason_days': null,
        'reason_bucket': 'week',
        'reason_on_hand': null,
        'reason_lot_is_open': null,
        'reason_target': null,
        'reason_movement_count': 4,
        'checked_at': null,
      });

      expect(line.reason, ShoppingReason.roughlyDue);
      expect(line.bucket, 'week');
      expect(line.days, isNull);
    });

    test('an expiring line on an opened lot marks it, so the shorter clock applies', () {
      final ShoppingLine line = ShoppingLine.fromApi(<String, dynamic>{
        'id': 'line-3',
        'product_id': 'p-3',
        'name': 'Yoğurt 2 kg',
        'quantity': 1,
        'unit': 'C62',
        'reason': 'expiring',
        'reason_days': 3,
        'reason_bucket': null,
        'reason_on_hand': null,
        'reason_lot_is_open': true,
        'reason_target': null,
        'reason_movement_count': 0,
        'checked_at': null,
      });

      expect(line.reason, ShoppingReason.expiring);
      expect(line.days, 3);
      expect(line.lotIsOpen, isTrue);
    });

    test('a manual line has no product and can already be checked', () {
      final ShoppingLine line = ShoppingLine.fromApi(<String, dynamic>{
        'id': 'line-4',
        'product_id': null,
        'name': 'Bulaşık deterjanı',
        'quantity': 1,
        'unit': 'H87',
        'reason': 'manual',
        'reason_days': null,
        'reason_bucket': null,
        'reason_on_hand': null,
        'reason_lot_is_open': null,
        'reason_target': null,
        'reason_movement_count': 0,
        'checked_at': '2026-09-01T10:00:00+00:00',
      });

      expect(line.productId, isNull);
      expect(line.reason, ShoppingReason.manual);
      expect(line.isChecked, isTrue);
    });
  });
}
