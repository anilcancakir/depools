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

  /// Strings that look like copy and are not.
  bool isAllowed(String value) {
    // Recipe slot names and className fragments: identifiers that happen to be capitalised.
    if (RegExp(r'^[a-z][A-Za-z]*$').hasMatch(value)) return true;
    // Assertion messages, read by whoever has a stack trace rather than by a user.
    if (value.contains('Draft:') || value.contains('needs two places')) return true;
    return false;
  }

  test('no user-visible copy is hardcoded in a view or a component', () {
    final List<String> offenders = <String>[];

    // **`lib/app` is NOT in this list and that is a known hole, not an oversight.** A controller or a
    // domain model there can hold user-visible copy and never be looked at. Measured by adding it
    // temporarily: `product_filter.dart` returns five hardcoded Turkish filter labels today, so an
    // English interface shows Turkish in its filter control, and `app_service_provider.dart` names
    // `Türkçe`, which is correctly NOT translated because a language endonym never is.
    //
    // Closing it means localising those labels and giving the endonym an allowance, which is a change
    // to an unrelated model and belongs on its own. Recorded here so the next person finds the
    // measurement rather than the surprise.
    //
    // Worth knowing before widening it: the check below tests for TURKISH CHARACTERS, not for copy.
    // `Stok yok`, `Az kalan` and `Stokta` are hardcoded Turkish in that same file and no version of
    // this scan will ever flag them, because they are spelled in ASCII.
    for (final String base in <String>['lib/resources/views', 'lib/ui/components']) {
      for (final FileSystemEntity entity in Directory(base).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (entity.path.endsWith('.preview.dart')) continue;
        if (entity.path.contains('fixtures')) continue;

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

          for (final RegExpMatch match in literal.allMatches(line)) {
            final String value = match.group(1)!;
            if (!turkish.hasMatch(value)) continue;
            if (isAllowed(value)) continue;
            offenders.add('${entity.path}: $value');
          }
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Move these into assets/lang/*.json and read them with Lang.get, or mark the block '
          'as demo data:\n${offenders.join('\n')}',
    );
  });
}
