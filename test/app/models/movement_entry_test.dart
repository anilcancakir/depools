import 'package:depools/app/models/movement_entry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';

/// Decoding a ledger row into [MovementEntry], the wire shape
/// `lib/resources/views/dashboard_fixtures.dart`'s own `MovementEntry(...)` constructor already
/// writes (see that class's docblock: "writes the same wire shape `fromMap` reads").
///
/// `fromMap` is the one accessor in this batch that kept an explicit guard (`reason is! String ||
/// delta is! num`) rather than defaulting through a null-coalescing getter, because a row with
/// neither field is not a movement at all; both branches of that guard get their own case here.
void main() {
  group('MovementEntry.fromMap', () {
    test('a purchase row decodes the actor, the location and the product it names', () {
      final MovementEntry? entry = MovementEntry.fromMap(<String, dynamic>{
        'reason': 'purchase',
        'delta': 6,
        'entered_quantity': 6,
        'entered_unit': 'C62',
        'actor_type': 'user',
        'actor_name': 'Anıl',
        'location_name': 'Kiler › Raf 1',
        'product_name': 'Pınar Süt Tam Yağlı 1 lt',
        'occurred_at': '2026-09-02T08:00:00+00:00',
      });

      expect(entry, isNotNull);
      expect(entry!.reason, 'purchase');
      expect(entry.delta, 6.0);
      expect(entry.enteredQuantity, 6.0);
      expect(entry.enteredUnit, 'C62');
      expect(entry.actorType, 'user');
      expect(entry.actorName, 'Anıl');
      expect(entry.locationName, 'Kiler › Raf 1');
      expect(entry.productName, 'Pınar Süt Tam Yağlı 1 lt');
      expect(entry.at, DateTime.parse('2026-09-02T08:00:00+00:00'));
    });

    test('delta and occurred_at decode through their declared casts', () {
      final MovementEntry? entry = MovementEntry.fromMap(<String, dynamic>{
        'reason': 'consumption',
        'delta': -1,
        'occurred_at': '2026-09-02T10:00:00+00:00',
      });

      expect(entry, isNotNull);
      // `delta` is cast `'double'`: an int payload still reads back as a double, not the raw int.
      expect(entry!.getAttribute('delta'), isA<double>());
      expect(entry.delta, -1.0);
      // `occurred_at` is cast `'datetime'`: the raw attribute is a Carbon, not the ISO string it
      // arrived as. `MovementEntry.at` unwraps it to the plain DateTime the screen reads.
      expect(entry.getAttribute('occurred_at'), isA<Carbon>());
      expect(entry.at, isA<DateTime>());
    });

    test('a row missing the reason cannot be read', () {
      expect(
        MovementEntry.fromMap(<String, dynamic>{'delta': -2}),
        isNull,
      );
    });

    test('a row missing the delta cannot be read', () {
      expect(
        MovementEntry.fromMap(<String, dynamic>{'reason': 'waste'}),
        isNull,
      );
    });
  });
}
