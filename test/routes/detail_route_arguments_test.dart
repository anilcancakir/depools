import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// What a detail route is handed, read from the source of the screens that navigate.
///
/// **`/products/:id` and `/locations/:id` match ANY segment, so a display string routes cleanly and
/// resolves to nothing.** Neither the analyzer nor a widget test can see it: the interpolation is a
/// valid `String` either way, and the app navigates without complaint. What the user gets is a
/// screen that never fills in, which is how `location_show_view.dart` shipped a tap that put a
/// materialised path (`Storeroom › Shelf A`) into the URL and rendered an empty page.
///
/// The index screen had already been corrected to send the id, and the detail screen was left
/// behind. That is the shape this file exists to stop: a fix applied to the instance rather than to
/// the class.
///
/// The rule is a prohibition rather than a whitelist, deliberately. `Uri.encodeComponent(id)` is
/// fine, `child.id` is fine, and an expression naming `name` or `path` is a display string wherever
/// it came from.
void main() {
  /// Every `MagicRoute.to('/<detail>/${<expression>}')` in the view layer, as (file, route, expr).
  final RegExp navigation = RegExp(
    r"""MagicRoute\.to\(\s*'/(products|locations)/\$\{([^}]*)\}'\s*\)""",
  );

  late List<(String file, String route, String expression)> destinations;

  setUpAll(() {
    destinations = <(String, String, String)>[];

    final Iterable<File> views = Directory('lib/resources/views')
        .listSync(recursive: true)
        .whereType<File>()
        .where((File f) => f.path.endsWith('.dart'));

    for (final File view in views) {
      for (final RegExpMatch match in navigation.allMatches(view.readAsStringSync())) {
        destinations.add((view.path, match.group(1)!, match.group(2)!));
      }
    }
  });

  test('the views are read at all, so an empty match cannot pass this file', () {
    // The guard on the guard, in the shape `route_paths_test` already uses: a scanner that stops
    // matching reports a clean app forever, which is worse than no scanner. Six parameterised
    // destinations exist across the product, search and location screens.
    expect(destinations.length, greaterThanOrEqualTo(6));
    expect(destinations.map((d) => d.$2).toSet(), containsAll(<String>['products', 'locations']));
  });

  test('a detail route is handed an identifier, never a name or a path', () {
    final Iterable<(String, String, String)> offenders = destinations.where(
      (d) => RegExp(r'\b(name|path)\b').hasMatch(d.$3),
    );

    expect(
      offenders,
      isEmpty,
      reason: offenders
          .map((d) => '${d.$1} routes to /${d.$2}/ with "${d.$3}"')
          .join('\n'),
    );
  });
}
