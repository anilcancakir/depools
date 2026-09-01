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

    test('a string with two inflecting counts is composed, not piped once', () {
      // A single pipe can only be right about ONE noun, so a value carrying two independently
      // varying counts and one pipe is wrong for every case where they differ. `committed_counted`
      // shipped that way: keyed on the row count while `:written changes written` varied on its own,
      // and rows-versus-changes differ routinely, because a matching count writes nothing.
      //
      // The shape that works is two pluralised fragments and a wrapper holding the separator, which
      // is also what keeps the composition inside the copy rule. So: a value with a pipe carries at
      // most one placeholder that a count drives.
      final RegExp placeholder = RegExp(r':[a-z_]+');
      const Set<String> countNames = <String>{
        ':count', ':counted', ':written', ':variances', ':matched', ':skipped', ':unfinished',
      };

      // **A count followed by a participle drives no inflection, and this test cannot tell.** It
      // reads placeholder names, not English grammar, so a value where the extra count is followed by
      // `counted`, `matched`, `skipped` or `left` has to be exempted by hand. Recorded rather than
      // silently widened, so the exception is a decision instead of a hole:
      //
      // - `summary`: `:counted counted · :variances differences`. `counted` is a participle and
      //   agrees with nothing; `difference` is the noun that inflects, and the pipe is keyed on
      //   `:variances`. It used to end in the VERB `differ`, whose singular half rendered `1 differs`,
      //   a verb with no subject; the Turkish side had `fark` as a noun all along, so this was the
      //   English drifting rather than a translation lagging.
      const Set<String> participleClauses = <String>{'screens.stock_take.summary'};

      for (final MapEntry<String, String> entry in en.entries) {
        if (!entry.value.contains('|')) continue;
        if (participleClauses.contains(entry.key)) continue;

        final Set<String> counts = placeholder
            .allMatches(entry.value)
            .map((m) => m.group(0)!)
            .where(countNames.contains)
            .toSet();

        // `:matched` is a participle in English too, so it may ride along anywhere.
        counts.remove(':matched');

        expect(
          counts.length,
          lessThanOrEqualTo(1),
          reason: '${entry.key} pipes on one noun while carrying ${counts.length} counts: $counts. '
              'Split it into fragments and compose them through a wrapper key.',
        );
      }
    });

    test('every piped key is read through plural, never through Lang.get', () {
      // **Piping a key without sweeping its callers is worse than the bug it fixes.** `Lang.get`
      // returns the whole value, so a key that gained a `|` renders `1 location|1 locations` at the
      // user: a plural defect turned into a visibly broken string.
      //
      // Nearly walked into exactly that: `screens.location.location_count` gained a pipe for the
      // detail screen while the search screen still read it with `Lang.get`, on a screen the change
      // was not about.
      final RegExp call = RegExp(r"Lang\.get\(\s*'([^']+)'");
      final Set<String> piped = <String>{
        for (final MapEntry<String, String> entry in en.entries)
          if (entry.value.contains('|')) entry.key,
        for (final MapEntry<String, String> entry in tr.entries)
          if (entry.value.contains('|')) entry.key,
      };

      final List<String> offenders = <String>[];

      for (final FileSystemEntity file in Directory('lib').listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;

        final String source = file.readAsStringSync();

        for (final RegExpMatch match in call.allMatches(source)) {
          if (piped.contains(match.group(1))) {
            offenders.add('${file.path}: ${match.group(1)}');
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason: 'these read a plural key with Lang.get, so the pipe renders at the user:\n'
            '${offenders.join('\n')}',
      );
    });

    test('an English count before a plural noun carries a pipe', () {
      // The guards above all fire once a key HAS a pipe. Nothing fired on a key that needed one and
      // never got it, which is how `:count regions` and `Add :count products` reached a screenshot
      // reading `1 regions were not recognised` and `Add 1 products` on the shelf screen.
      //
      // A count placeholder immediately followed by a word ending in `s` is the shape, and it is
      // syntactic rather than grammatical: it cannot tell a plural noun from a participle, so the
      // exemptions below are read by hand rather than pattern-matched.
      const Set<String> counts = <String>{
        ':count', ':counted', ':total', ':regions', ':lines', ':ready', ':unresolved', ':written',
        ':variances', ':skipped', ':unfinished', ':n',
      };

      // **These 27 predate the guard and are debt, listed rather than swept.** Each renders a
      // disagreeing string at exactly one count (`1 batches`, `Save 1 lines`, `1 programs`), and
      // fixing them means touching six screens this test's own change is not about. The list is here
      // so the debt is countable and so nothing new can join it: a new key with this shape fails.
      const Set<String> pending = <String>{
        'screens.assistant.chip_expiring_label',
        'screens.assistant.chip_low_label',
        'screens.assistant.chip_untargeted_label',
        'screens.assistant.shopping_count',
        'screens.dashboard.count_batches',
        'screens.dashboard.count_changes',
        'screens.dashboard.count_products',
        'screens.dashboard.setup_count',
        'screens.dashboard.shopping_count',
        'screens.labels.label_count',
        'screens.locations.filtered_hint',
        'screens.locations.subtitle',
        'screens.mcp.client_count',
        'screens.product.activity_count',
        'screens.product.barcode_count',
        'screens.product.locations_count',
        'screens.product.serial_count',
        'screens.product.stat_forecast_progress',
        'screens.product_filter.apply',
        'screens.products.filtered_description',
        'screens.products.subtitle',
        'screens.products.subtitle_filtered',
        'screens.receipt.line_count',
        'screens.receipt.submit',
        'screens.receipt.subtitle',
        'screens.stock_in.suggested_category',
        'screens.stock_move.suggested_count',
      };

      final RegExp shape = RegExp('(${counts.join('|')}) ([a-z]+)');

      final List<String> offenders = <String>[];

      for (final MapEntry<String, String> entry in en.entries) {
        if (entry.value.contains('|') || pending.contains(entry.key)) continue;

        for (final RegExpMatch match in shape.allMatches(entry.value)) {
          if (match.group(2)!.endsWith('s')) {
            offenders.add('${entry.key} = ${entry.value}');
            break;
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason: 'these agree with no count, so one value renders wrong:\n${offenders.join('\n')}',
      );

      // The debt list shrinks; it does not grow. A key fixed and left listed would make the list a
      // lie, and a key removed from the catalogue would make it stale.
      for (final String key in pending) {
        expect(
          en.containsKey(key),
          isTrue,
          reason: '$key is listed as pending plural debt and no longer exists',
        );
        expect(
          en[key]!.contains('|'),
          isFalse,
          reason: '$key now carries a pipe, so drop it from the pending list',
        );
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
