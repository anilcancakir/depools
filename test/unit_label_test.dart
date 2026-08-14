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
  /// Every code the units migration seeds. Kept here rather than derived from the catalogue, because a
  /// list read out of the thing under test cannot notice a code missing from it.
  const List<String> seeded = <String>[
    'C62',
    'KGM',
    'GRM',
    'LTR',
    'MLT',
    'MTR',
    'PK',
    'BX',
    'CT',
  ];

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

  test('English inflects the words and Turkish inflects nothing', () {
    // After a numeral Turkish does not inflect, so `1 adet` and `5 adet` are both right and one half is
    // the whole answer. English needs the pipe `plural()` reads. Symbols (`kg`, `ml`) inflect in
    // neither, which is why this asserts the WORDS rather than every entry.
    const List<String> words = <String>['c62', 'pk', 'bx', 'ct'];

    for (final String key in words) {
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

    for (final String key in <String>['kgm', 'grm', 'ltr', 'mlt', 'mtr']) {
      expect(units('en')[key], isNot(contains('|')), reason: 'en: $key is a symbol');
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
}
