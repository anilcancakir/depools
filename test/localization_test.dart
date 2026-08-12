import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The translation catalogues, locked against the one failure mode that is silent.
///
/// magic's `Translator` REPLACES its sentence map when a locale loads rather than merging with the
/// fallback: `_sentences = data.map(...)` and then `_sentences[key] ?? key`. So a key present in
/// `en.json` and missing from `tr.json` does not fall back to English. It renders the KEY, and a
/// Turkish user reads `auth.login_title` on the login screen.
///
/// That makes catalogue completeness a build-time property rather than a translation nicety, and it
/// is invisible to `flutter analyze`, to `bin/design-tokens` and to any screenshot of a screen whose
/// keys happen to be covered. This file is the only thing standing between an added English string
/// and a raw key in production.
void main() {
  late Map<String, String> en;
  late Map<String, String> tr;

  Map<String, String> flatten(Map<String, dynamic> node, [String prefix = '']) {
    final Map<String, String> out = <String, String>{};
    node.forEach((String key, dynamic value) {
      final String path = prefix.isEmpty ? key : '$prefix.$key';
      if (value is Map<String, dynamic>) {
        out.addAll(flatten(value, path));
      } else {
        out[path] = value.toString();
      }
    });
    return out;
  }

  Map<String, String> load(String locale) {
    final File file = File('assets/lang/$locale.json');
    expect(file.existsSync(), isTrue, reason: 'assets/lang/$locale.json is missing');

    return flatten(jsonDecode(file.readAsStringSync()) as Map<String, dynamic>);
  }

  setUp(() {
    en = load('en');
    tr = load('tr');
  });

  test('tr covers every en key, because a miss renders the key itself', () {
    final Set<String> missing = en.keys.toSet().difference(tr.keys.toSet());

    expect(missing, isEmpty, reason: 'these keys would render as raw text in Turkish: $missing');
  });

  test('tr carries no key en does not, so a stale entry cannot hide a rename', () {
    // A key that exists only in `tr` is either a typo or the remains of a rename, and both look
    // identical to a working translation until someone reads the screen.
    final Set<String> orphans = tr.keys.toSet().difference(en.keys.toSet());

    expect(orphans, isEmpty, reason: 'these tr keys have no en counterpart: $orphans');
  });

  test('no value is empty in either catalogue', () {
    for (final MapEntry<String, String> entry in <MapEntry<String, String>>[...en.entries, ...tr.entries]) {
      expect(entry.value.trim(), isNotEmpty, reason: '${entry.key} is blank');
    }
  });

  test('every :placeholder survives translation', () {
    // The load-bearing one. `validation.min` is `The :attribute must be at least :min characters.`
    // and a Turkish rewrite that drops `:min` produces a rule that never names its own limit. The
    // failure is silent: the sentence still reads as a sentence.
    final RegExp placeholder = RegExp(r':[a-z_]+');

    for (final String key in en.keys) {
      final Set<String> expected = placeholder.allMatches(en[key]!).map((m) => m.group(0)!).toSet();
      final Set<String> actual = placeholder.allMatches(tr[key]!).map((m) => m.group(0)!).toSet();

      expect(actual, equals(expected), reason: '$key lost or invented a placeholder');
    }
  });

  test('the app name is the product name in both', () {
    // It shipped as `My App`, which is what the shell's app bar rendered until someone looked.
    expect(en['app.name'], 'Depools');
    expect(tr['app.name'], 'Depools');
  });

  group('plural forms', () {
    // `magic`'s `Lang` has no `choice`, so `lib/app/support/plural.dart` reads Laravel's own
    // `singular|plural` pipe out of the VALUE. Two ways that goes wrong are silent, and both render
    // text at the user rather than throwing.
    final RegExp placeholder = RegExp(r':[a-z_]+');

    test('a pipe splits into exactly two halves', () {
      // Three halves means one is unreachable, and a trailing pipe means one count renders nothing
      // at all. Neither is visible until somebody hits that count.
      for (final MapEntry<String, Map<String, String>> catalogue
          in <String, Map<String, String>>{'en': en, 'tr': tr}.entries) {
        for (final MapEntry<String, String> entry in catalogue.value.entries) {
          if (!entry.value.contains('|')) continue;

          final List<String> halves = entry.value.split('|');

          expect(
            halves.length,
            2,
            reason: '${catalogue.key}: ${entry.key} has ${halves.length} halves',
          );

          for (final String half in halves) {
            expect(
              half.trim(),
              isNotEmpty,
              reason: '${catalogue.key}: ${entry.key} has an empty half, so one count renders nothing',
            );
          }
        }
      }
    });

    test('both halves interpolate the same names', () {
      // The halves are interchangeable at runtime, so a placeholder in one and not the other prints
      // a literal `:count` for exactly one count and reads correctly for every other.
      for (final MapEntry<String, Map<String, String>> catalogue
          in <String, Map<String, String>>{'en': en, 'tr': tr}.entries) {
        for (final MapEntry<String, String> entry in catalogue.value.entries) {
          if (!entry.value.contains('|')) continue;

          final List<String> halves = entry.value.split('|');

          expect(
            placeholder.allMatches(halves.last).map((m) => m.group(0)!).toSet(),
            placeholder.allMatches(halves.first).map((m) => m.group(0)!).toSet(),
            reason: '${catalogue.key}: ${entry.key} halves do not interpolate the same names',
          );
        }
      }
    });

    test('a locale that inflects carries a pipe wherever the other one does', () {
      // Turkish does not inflect after a numeral, so a `tr` value with no pipe is correct rather
      // than incomplete. English is the other way round: a pipe in `tr` and none in `en` means the
      // English string agrees with nothing, which is the defect this whole helper exists for.
      for (final String key in tr.keys) {
        if (!tr[key]!.contains('|')) continue;

        expect(
          en[key]!.contains('|'),
          isTrue,
          reason: '$key inflects in Turkish and not in English, which is backwards',
        );
      }
    });
  });
}
