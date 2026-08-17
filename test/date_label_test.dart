import 'dart:ui';

import 'package:depools/app/support/date_label.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';

/// `dateLabel` moved out of `stock_in_sheet.dart` verbatim, so what this pins is the ARITHMETIC:
/// the right month index and the year rule, not the translated word.
///
/// ### Why the assertions read a raw key rather than "Ağu"
///
/// Measured the same way `unit_label_test.dart` measured it for `unitLabel`: `Lang.setLocale`
/// flips `Lang.isLoaded` to true and sets `Lang.current` correctly, because `Translator.load`
/// sets both unconditionally, but the catalogue fetch itself never completes under the plain
/// `flutter test` binding, so the sentence map stays empty and `Lang.get('common.months.8')`
/// answers with the key itself. Asserting `dateLabel(...) == '5 Ağu'` here would therefore be
/// asserting the MISS path while claiming the hit, exactly the trap that file's docblock names.
/// So the assertions below read `'${day} common.months.${month}'`, which is what `dateLabel`
/// actually produces in this harness and is still able to catch an off-by-one on the month
/// index or a year that should or should not have been dropped: the two things this extraction
/// has to get right to be a faithful move.
void main() {
  setUp(() async {
    // `dateLabel` does not itself read `Lang.current`, but the locale is switched anyway so a
    // future dependency on it cannot slip past this file unnoticed.
    await Lang.setLocale(const Locale('en'), reload: false);
  });

  test('a date in the current year carries no year', () {
    final DateTime now = DateTime.now();
    final DateTime date = DateTime(now.year, 6, 15);

    expect(dateLabel(date), '15 common.months.6');
  });

  test('a date outside the current year carries it', () {
    final DateTime now = DateTime.now();
    final DateTime date = DateTime(now.year + 2, 6, 15);

    // A two-year warranty rendering the bare day is the defect this rule exists to prevent: it
    // read as this week rather than two years out.
    expect(dateLabel(date), '15 common.months.6 ${now.year + 2}');
  });

  test('January resolves to month index 1, not 0', () {
    final DateTime now = DateTime.now();
    final DateTime date = DateTime(now.year, 1, 3);

    expect(dateLabel(date), '3 common.months.1');
  });

  test('December resolves to month index 12, not 11', () {
    final DateTime now = DateTime.now();
    final DateTime date = DateTime(now.year, 12, 31);

    expect(dateLabel(date), '31 common.months.12');
  });

  test('the same date and rule hold under the Turkish locale too', () async {
    await Lang.setLocale(const Locale('tr'), reload: false);

    final DateTime now = DateTime.now();
    final DateTime thisYear = DateTime(now.year, 1, 3);
    final DateTime otherYear = DateTime(now.year - 3, 12, 31);

    expect(dateLabel(thisYear), '3 common.months.1');
    expect(dateLabel(otherYear), '31 common.months.12 ${now.year - 3}');
  });
}
