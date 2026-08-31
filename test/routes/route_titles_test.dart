import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every route carries a page title, and the key behind it resolves in both languages.
///
/// **The browser tab is the surface this protects.** `TitleManager` resolves an override, then the
/// route title, then the app title, so a route with no title of its own leaves every screen in the
/// app reading `Depools` in the tab, the history entry and the bookmark. On web that is the one
/// piece of chrome the app does not draw itself, and nothing else in this repository can see it go
/// wrong: the analyzer cannot, because a missing builder call is valid code, and a screenshot
/// cannot, because the tab is outside the canvas.
///
/// **The second half is the one a green suite hides.** `localization_test` compares the two
/// catalogues against EACH OTHER, so a key neither of them holds passes it, and
/// `no_hardcoded_copy_test` passes too because the title is not a literal. The screen would then
/// render `screens.plan.title` at the reader. So presence is asserted here, against both files.
///
/// Read from the source text rather than from a booted router, for the reason
/// `route_paths_test.dart` gives: reading the framework's table back needs `Magic.init`, a config
/// load and an asset bundle to answer a question the file answers exactly.
void main() {
  // One registration is `MagicRoute.page(` up to the `);` that closes its builder chain. Matching
  // the whole chain rather than a fixed `.name().title()` order is deliberate: the order of the
  // builders is a style choice and this test has no business pinning one.
  final RegExp registration = RegExp(r'MagicRoute\.page\([\s\S]*?\);');
  final RegExp name = RegExp(r"\.name\('([^']+)'\)");
  final RegExp title = RegExp(r"\.title\('([^']+)'\)");

  late List<String> registrations;
  late Map<String, dynamic> english;
  late Map<String, dynamic> turkish;

  /// Walks a dotted key through a catalogue, answering null when any segment is missing.
  Object? lookup(Map<String, dynamic> catalogue, String key) {
    Object? node = catalogue;

    for (final String segment in key.split('.')) {
      if (node is! Map<String, dynamic>) return null;

      node = node[segment];
    }

    return node;
  }

  setUpAll(() {
    registrations = registration
        .allMatches(File('lib/routes/app.dart').readAsStringSync())
        .map((RegExpMatch match) => match.group(0)!)
        .toList();

    english = jsonDecode(File('assets/lang/en.json').readAsStringSync()) as Map<String, dynamic>;
    turkish = jsonDecode(File('assets/lang/tr.json').readAsStringSync()) as Map<String, dynamic>;
  });

  test('the table is read at all, so an empty match cannot pass this file', () {
    // The guard on the guard, copied from `route_paths_test`: a regex that stops matching reports a
    // clean table forever, and a checker whose broken state looks like success is worse than none.
    expect(registrations.length, greaterThanOrEqualTo(18));
    expect(registrations.every((String source) => name.hasMatch(source)), isTrue);
  });

  test('every route carries a title', () {
    for (final String source in registrations) {
      final String route = name.firstMatch(source)?.group(1) ?? source;

      expect(
        title.hasMatch(source),
        isTrue,
        reason: 'the $route route has no .title(), so its tab would read the app name',
      );
    }
  });

  test("the starter's own twenty titles resolve too", () {
    // `magic_starter` alpha.24 gave its 20 routes titles and shipped the keys in its INSTALL stub,
    // which an app installed before that release never received. The tab then read
    // `magic_starter.titles.login` at the user, measured over CDP on the login screen. Note that
    // `starter:doctor` reported `Translations: OK` throughout, so it is not a gate for this.
    //
    // A count rather than the key list: the list lives in another repository and reading it from a
    // path dependency would resolve differently in CI, where the package comes from the pub cache.
    // So this catches the block being dropped and it does NOT catch the starter adding a
    // twenty-first title. Driving the app and reading `document.title` is what catches that.
    for (final (String language, Map<String, dynamic> catalogue) in <(String, Map<String, dynamic>)>[
      ('en', english),
      ('tr', turkish),
    ]) {
      final Object? titles = lookup(catalogue, 'magic_starter.titles');

      expect(
        titles,
        isA<Map<String, dynamic>>(),
        reason: 'magic_starter.titles is missing from $language.json',
      );
      expect((titles! as Map<String, dynamic>).length, greaterThanOrEqualTo(20));
    }
  });

  test('every title key resolves in both catalogues', () {
    for (final String source in registrations) {
      final String? key = title.firstMatch(source)?.group(1);

      if (key == null) continue;

      expect(
        lookup(english, key),
        isA<String>(),
        reason: '$key is missing from en.json, so the tab would render the key itself',
      );
      expect(
        lookup(turkish, key),
        isA<String>(),
        reason: '$key is missing from tr.json, so the tab would render the key itself',
      );
    }
  });
}
