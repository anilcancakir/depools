import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the thing that is easy to undo one line at a time.
///
/// `iterations.md` requires complete Turkish AND English for v1 and says the MVP's 25 percent
/// coverage will not repeat. It repeated anyway, because a literal in a widget is invisible: it
/// renders perfectly, reviews cleanly, and only fails for a user in the other language.
///
/// This walks every view and component and fails on a Turkish-looking string.
///
/// ### Demo data is marked at the site rather than listed here
///
/// Fixtures are not translated, because they stand in for user data and a user's own product name
/// is not translated either. Most of them live in a `*_fixtures.dart` file, which this skips by
/// path. The rest are inline demo rows inside a view, and they carry an explicit marker:
///
/// ```dart
/// // demo-data-start: the transcript the assistant preview renders
/// ...
/// // demo-data-end
/// ```
///
/// A marker rather than an allow-list, because the allow-list would live here and the decision
/// belongs where the data is. It also makes the demo blocks greppable when the backend replaces
/// them.
void main() {
  final RegExp turkish = RegExp('[çğıöşüÇĞİÖŞÜ]');
  final RegExp literal = RegExp(r"'([^'\n]{3,})'");
  final RegExp textLiteral = RegExp(r"WText\(\s*'([^'\n]*)'");
  final RegExp interpolation = RegExp(r'\$\{[^}]*\}|\$[A-Za-z_][A-Za-z0-9_]*');
  final RegExp letter = RegExp('[A-Za-z]');

  /// Strings that look like copy and are not.
  bool isAllowed(String value) {
    // Recipe slot names and className fragments: identifiers that happen to be capitalised.
    if (RegExp(r'^[a-z][A-Za-z]*$').hasMatch(value)) return true;
    // Assertion messages, read by whoever has a stack trace rather than by a user.
    if (value.contains('Draft:') || value.contains('needs two places')) return true;
    return false;
  }

  /// Every view and component, as source with the comments and the demo blocks taken out.
  ///
  /// Shared by both tests so the fixture paths, the preview exclusion and the demo markers are
  /// decided in one place. Comment lines go because a comment quoting an offender is not one, and
  /// the joined result is scanned whole rather than line by line so a call broken across lines is
  /// still a call.
  Map<String, String> code() {
    final Map<String, String> sources = <String, String>{};

    for (final String base in <String>['lib/resources/views', 'lib/ui/components']) {
      for (final FileSystemEntity entity in Directory(base).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (entity.path.endsWith('.preview.dart')) continue;
        if (entity.path.contains('fixtures')) continue;

        final List<String> kept = <String>[];
        bool inDemo = false;

        for (final String line in entity.readAsLinesSync()) {
          final String trimmed = line.trimLeft();

          if (trimmed.startsWith('// demo-data-start')) {
            inDemo = true;
            continue;
          }
          if (trimmed.startsWith('// demo-data-end')) {
            inDemo = false;
            continue;
          }
          if (inDemo || trimmed.startsWith('//')) continue;

          kept.add(line);
        }

        sources[entity.path] = kept.join('\n');
      }
    }

    return sources;
  }

  test('no user-visible copy is hardcoded in a view or a component', () {
    final List<String> offenders = <String>[];

    // **`lib/app` is NOT scanned and that is a known hole, not an oversight.** A controller or a
    // domain model there can hold user-visible copy and never be looked at. Measured by adding it
    // temporarily: `product_filter.dart` returns five hardcoded Turkish filter labels today, so an
    // English interface shows Turkish in its filter control, and `app_service_provider.dart` names
    // `Türkçe`, which is correctly NOT translated because a language endonym never is.
    //
    // Closing it means localising those labels and giving the endonym an allowance, which is a change
    // to an unrelated model and belongs on its own. Recorded here so the next person finds the
    // measurement rather than the surprise.
    //
    // Worth knowing before widening it: this check tests for TURKISH CHARACTERS, not for copy.
    // `Stok yok`, `Az kalan` and `Stokta` are hardcoded Turkish in that same file and no version of
    // this scan will ever flag them, because they are spelled in ASCII. The test below covers the
    // one shape of ASCII copy that can be recognised without a dictionary.
    code().forEach((String path, String source) {
      for (final RegExpMatch match in literal.allMatches(source)) {
        final String value = match.group(1)!;
        if (!turkish.hasMatch(value)) continue;
        if (isAllowed(value)) continue;
        offenders.add('$path: $value');
      }
    });

    expect(
      offenders,
      isEmpty,
      reason: 'Move these into assets/lang/*.json and read them with Lang.get, or mark the block '
          'as demo data:\n${offenders.join('\n')}',
    );
  });

  test('no WText builds its own sentence out of an interpolated literal', () {
    // **The scan above looks for Turkish CHARACTERS, so an ASCII Turkish word walks past it.**
    // `'$c · $count seri'` shipped on the label row that way, and `'$count etiket'` sat one branch
    // below it through the review that fixed the first. Both were also invisible to
    // `localization_test`, which can only check a placeholder that reached a catalogue.
    //
    // So this closes the SHAPE rather than the vocabulary, which is the only half a test can decide
    // without a dictionary: a `WText` whose literal carries a `$` AND a letter of its own is
    // building a sentence in Dart, whatever language the letters are in. A bare `'$count'` or
    // `'${row.index}'` is a number and stays allowed, which is why the interpolations are stripped
    // before the letters are counted rather than after.
    final List<String> offenders = <String>[];

    code().forEach((String path, String source) {
      for (final RegExpMatch match in textLiteral.allMatches(source)) {
        final String value = match.group(1)!;

        if (!value.contains(r'$')) continue;
        if (!letter.hasMatch(value.replaceAll(interpolation, ''))) continue;

        offenders.add('$path: $value');
      }
    });

    expect(
      offenders,
      isEmpty,
      reason: 'Interpolation belongs in the catalogue as a :placeholder, so the other language can '
          'put the number somewhere else and inflect around it:\n${offenders.join('\n')}',
    );
  });
}
