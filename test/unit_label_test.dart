import 'dart:convert';
import 'dart:io';

import 'package:depools/app/support/unit_label.dart';
import 'package:flutter_test/flutter_test.dart';

/// A stored unit code becomes a word, which is what stopped `1 adet` reaching an English screen.
///
/// The codes are UN/ECE Rec 20 and unreadable by design, so this indirection is the only thing between
/// the database and the reader.
///
/// ### Why the catalogue is read as a FILE and the hit path is not driven here
///
/// A test binding reports `Lang.isLoaded` as true and then resolves nothing: measured, with
/// `screens.scan.title` coming back as its own key alongside `units.c62`. So a test asserting
/// `unitLabel('C62') == 'piece'` in this harness would be asserting the MISS path while claiming the
/// hit, which is worse than not testing it.
///
/// So the two halves are split honestly. The catalogue's CONTENT is checked against the file, the same
/// technique `localization_test` uses for the same reason. The FALLBACK, which is the branch that runs
/// when a code has no entry, is checked through the helper. The hit path is verified by driving the
/// screen, where the catalogue really is loaded.
void main() {
  /// Every code the units migration seeds, split by whether its label is a WORD or a SYMBOL.
  ///
  /// **Kept here rather than derived from the catalogue**, because a list read out of the thing under
  /// test cannot notice a code missing from it. And split, because the two halves are asserted
  /// differently: an English word inflects after a numeral and a symbol does not.
  ///
  /// This list said nine after the migration grew to nineteen, which a review round caught. That is the
  /// failure mode of a hand-kept list, so it is worth saying what keeps it honest: the counts below are
  /// asserted against the total, so a code added to the migration and forgotten here fails rather than
  /// being quietly skipped.
  const List<String> words = <String>[
    'C62', 'DZN', 'PR', 'SET', 'PK', 'BX', 'CT', 'CS', 'BG', 'ROL',
  ];

  const List<String> symbols = <String>['TNE', 'KGM', 'GRM', 'MGM', 'LTR', 'MLT', 'MTR', 'CMT', 'MMT'];

  const List<String> seeded = <String>[...words, ...symbols];

  Map<String, dynamic> units(String locale) {
    final Map<String, dynamic> catalogue =
        jsonDecode(File('assets/lang/$locale.json').readAsStringSync()) as Map<String, dynamic>;

    return catalogue['units'] as Map<String, dynamic>;
  }

  test('every seeded code has a word in both languages', () {
    // Neither Dart nor PHP hands over a localised unit word: CLDR has them and `intl` exposes none of
    // it. So each code is one hand-written translation, and a missing one renders the raw code at the
    // user, which is the exact defect this whole change exists to fix.
    for (final String locale in <String>['en', 'tr']) {
      final Map<String, dynamic> words = units(locale);

      for (final String code in seeded) {
        final Object? word = words[code.toLowerCase()];

        expect(
          word,
          isA<String>(),
          reason: '$locale has no word for $code, so a screen would print the code',
        );
        expect((word as String).trim(), isNotEmpty, reason: '$locale: $code is blank');
      }
    }
  });

  test('the catalogue keys are lower case, because the helper folds before looking up', () {
    // Rec 20 codes are upper case (`KGM`) and these keys are not, so a mismatch here is a silent miss
    // for every unit at once.
    for (final String locale in <String>['en', 'tr']) {
      for (final String key in units(locale).keys) {
        expect(key, key.toLowerCase(), reason: '$locale: $key would never be found');
      }
    }
  });

  test('the catalogue covers exactly the seeded set and nothing else', () {
    // What keeps the hand-kept list above honest. A code added to the migration and forgotten here would
    // otherwise be skipped in silence, which is what happened when the set grew from nine to nineteen.
    for (final String locale in <String>['en', 'tr']) {
      expect(
        units(locale).keys.toSet(),
        seeded.map((String code) => code.toLowerCase()).toSet(),
        reason: '$locale: the catalogue and the seeded set have drifted apart',
      );
    }
  });

  test('English inflects every word and Turkish inflects nothing', () {
    // After a numeral Turkish does not inflect, so `1 adet` and `5 adet` are both right and one half is
    // the whole answer. English needs the pipe `plural()` reads.
    //
    // EVERY word, not a sample: this named four of the ten and a missing pipe on any of the other six
    // would have made `plural()` fall back silently to the singular for `5 boxes`.
    for (final String code in words) {
      final String key = code.toLowerCase();

      expect(
        units('en')[key],
        contains('|'),
        reason: 'en: $key is a word, so it needs a plural half',
      );
      expect(
        units('tr')[key],
        isNot(contains('|')),
        reason: 'tr: $key must not inflect after a numeral',
      );
    }

    // A symbol (`kg`, `ml`, `cm`) inflects in neither language, so a pipe there would be wrong rather
    // than merely unused.
    for (final String code in symbols) {
      expect(
        units('en')[code.toLowerCase()],
        isNot(contains('|')),
        reason: 'en: ${code.toLowerCase()} is a symbol',
      );
    }
  });

  test('a code with no entry is shown as it stands', () {
    // A tenant's own unit: the code IS their word for it, already in their language, so inventing a
    // translation slot would be inventing their vocabulary too. This is also what a shared code nobody
    // translated degrades to, which beats a blank.
    expect(unitLabel('KOLI'), 'KOLI');
    expect(unitLabel('koli'), 'koli', reason: 'their spelling, not a folded one');
  });

  test('an empty code stays empty rather than becoming a fallback nobody asked for', () {
    expect(unitLabel(''), '');
    expect(unitLabel('   '), '');
  });

  group('the count a formatted figure agrees with', () {
    // Most display sites hold only the string, because formatting is a locale decision belonging to
    // whoever built the figure, and the unit beside it still has to agree in number.
    //
    // **The COUNT is asserted rather than the word**, and that is not a shortcut. Every code falls
    // back to itself in this harness, for the reason the file docblock records, so
    // `unitLabelFor('C62', '1')` and `unitLabelFor('C62', '2')` both answer `C62` and an assertion on
    // them would pass whatever the rule did. The count is the part carrying a decision.

    test('exactly one is one, and nothing else is', () {
      expect(pluralCountOf('1'), 1);
      expect(pluralCountOf('2'), isNot(1));
      expect(pluralCountOf('0'), isNot(1));
    });

    test('a decimal written with a comma is read as the number it is', () {
      // `2,5` is how this locale writes it. A parse that did not know would still answer plural, but
      // by accident rather than by rule, and would then be wrong the day the rule changes.
      expect(pluralCountOf('2,5'), 2.5);
    });

    test('a grouped figure is not mistaken for one', () {
      // `1.240,00` does not parse, and `1.240` parses as 1.24 rather than 1240. Neither is 1, which
      // is the only distinction this makes, so both read as plural and both are right.
      expect(pluralCountOf('1.240,00'), isNot(1));
      expect(pluralCountOf('1.240'), isNot(1));
    });

    test('an empty or half-typed field reads as plural', () {
      // The placeholder in a stepper sits under a unit, not under a count of one.
      expect(pluralCountOf(''), isNot(1));
      expect(pluralCountOf('-'), isNot(1));
    });
  });
}
