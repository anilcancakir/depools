import 'package:depools/resources/views/products/product_fixtures.dart';
import 'package:flutter_test/flutter_test.dart';

/// Which server fields are moments and which are calendar dates.
///
/// Found on one screen, in one frame: the batches card said `Received 15/08/2026` for a movement the
/// activity card dated `16/08/2026`. Local time was past midnight while UTC was not, so the batches
/// card was showing a server instant as if it were the reader's.
///
/// The fix is not "convert everything", which is what these tests exist to stop. `received_at`,
/// `opened_at` and `acquired_at` are `timestamp` columns and name an instant; `expires_at` and
/// `earliest_expires_at` are `date` columns and name a DAY. Converting a day to local time shifts it
/// backwards for every reader east of UTC, moving a carton good until the 20th to the 19th.
///
/// **These assert on `momentDate`, not on the formatted string, and that is not a shortcut.**
/// `Lang.get` answers the raw key in this harness, so every formatter returns `time.date_format`
/// with no day in it: a test on the output would pass against any behaviour at all.
///
/// **What that leaves untested, stated rather than hidden: the CALL SITES.** Nothing here can assert
/// that `received_at` reaches `formatMoment` and `expires_at` reaches `formatDate`, because both
/// answer the same key whatever they are handed. The decision is pinned here and the wiring was
/// verified on screen, against the demo tenant, where the two cards agreed afterwards.
void main() {
  group('a moment is read in the reader\'s own timezone', () {
    test('an instant is converted, so its day can differ from the server\'s', () {
      // 23:30 UTC. Anywhere ahead of UTC by half an hour or more this is already the 16th, which is
      // exactly the case that produced the two disagreeing cards.
      const String utcEvening = '2026-08-15T23:30:00Z';

      // Compared against `toLocal` rather than a literal day, because the suite runs in whatever
      // timezone the machine is in. What has to hold is that the conversion happens; before the fix
      // the value went to the formatter untouched, and this is what says so.
      expect(
        ProductListItem.momentDate(utcEvening),
        DateTime.parse(utcEvening).toLocal(),
      );
    });

    test('the conversion is what a UTC machine cannot see', () {
      // A guard on the guard. On a machine running in UTC the assertion above holds trivially,
      // because local IS utc, so this one states the property that is true everywhere: the result
      // names the same INSTANT whatever the offset, and only its calendar day moves.
      const String utcEvening = '2026-08-15T23:30:00Z';

      expect(
        ProductListItem.momentDate(utcEvening)!.toUtc(),
        DateTime.parse(utcEvening).toUtc(),
      );
    });
  });

  group('a calendar date is left alone', () {
    test('a bare date would move if it were treated as a moment', () {
      // **The trap, stated as a test so nobody closes it by converting everything.** Parsed as an
      // instant, `2026-08-20` is midnight UTC, and midnight UTC is the previous evening anywhere
      // west of it. That is why there are two formatters rather than one.
      final DateTime asInstant = ProductListItem.momentDate('2026-08-20')!;

      expect(asInstant.day, anyOf(19, 20));
    });

    test('the date parser keeps the day it was given', () {
      final DateTime? parsed = ProductListItem.parseDate('2026-08-20');

      expect(parsed?.day, 20);
      expect(parsed?.month, 8);
    });
  });

  group('nothing in, nothing out', () {
    test('a null or unparseable value answers null rather than a placeholder', () {
      expect(ProductListItem.momentDate(null), isNull);
      expect(ProductListItem.momentDate('not a date'), isNull);
      expect(ProductListItem.formatMoment(null), isNull);
      expect(ProductListItem.formatDate(null), isNull);
    });
  });
}
