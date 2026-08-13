import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every key the app asks for exists in the catalogues.
///
/// **This is the gap `.claude/rules/flutter-app.md` describes and nothing enforced.** The other two
/// gates cannot see it, by construction: `localization_test` compares `en` and `tr` against EACH
/// OTHER, so a key neither has is perfect parity; `no_hardcoded_copy_test` looks for literal strings
/// in Dart, and `Lang.get('screens.x.y')` is not one. `flutter analyze` cannot help either, because a
/// key is a string.
///
/// So the screen renders `screens.stock_take.scan` at the user and the suite stays green. That is not
/// hypothetical: the scan control shipped that way into a dusk run today, which is where it was
/// caught, and the rule already said to check by hand after adding a `Lang.get`. A check that depends
/// on remembering is the one this replaces.
void main() {
  test('every key a Dart file asks for exists in both catalogues', () {
    // Only the literal form can be checked, which is most of them. A key built from a variable
    // (`'screens.x.$state'`) is invisible here and stays a reading exercise; matching a bare quoted
    // string means those simply do not appear rather than appearing as false positives.
    final RegExp call = RegExp(r"""Lang\.get\(\s*'([a-z0-9_.]+)'""");
    final RegExp pluralCall = RegExp(r"""plural\(\s*'([a-z0-9_.]+)'""");

    Map<String, dynamic> catalogue(String locale) =>
        jsonDecode(File('assets/lang/$locale.json').readAsStringSync()) as Map<String, dynamic>;

    bool has(Map<String, dynamic> tree, String key) {
      Object? node = tree;

      for (final String part in key.split('.')) {
        if (node is! Map<String, dynamic>) return false;

        node = node[part];
      }

      return node is String;
    }

    final Map<String, dynamic> en = catalogue('en');
    final Map<String, dynamic> tr = catalogue('tr');

    final List<String> missing = <String>[];

    for (final FileSystemEntity entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;

      final String source = entity.readAsStringSync();

      for (final RegExp pattern in <RegExp>[call, pluralCall]) {
        for (final RegExpMatch match in pattern.allMatches(source)) {
          final String key = match.group(1)!;

          // A key naming no section is a plain string somewhere else in the app's vocabulary, not a
          // screen key; the shape rule is `screens.<screen>.<key>` and `components.<name>.<key>`.
          if (!key.contains('.')) continue;

          if (!has(en, key)) missing.add('${entity.path}: $key (en)');
          if (!has(tr, key)) missing.add('${entity.path}: $key (tr)');
        }
      }
    }

    expect(
      missing,
      isEmpty,
      reason: 'these keys would render as raw text at the user:\n${missing.join('\n')}',
    );
  });
}
