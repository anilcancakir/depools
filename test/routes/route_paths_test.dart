import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The route table's shape, read from its source.
///
/// **A route path is a string, so nothing else in this repository can see one go wrong.** The
/// analyzer cannot, because it is a valid string either way; the widget tests cannot, because they
/// never navigate; and a screenshot cannot, because the app looks identical. The only two failures
/// that matter here are both silent: a path drifting back into Turkish, and a path disagreeing with
/// the name it is registered under.
///
/// Read from the file rather than from a booted router, deliberately. `MagicRoute.page` registers
/// into the framework's own table and reading it back would need `Magic.init`, a config load and an
/// asset bundle, which is a lot of machinery to answer a question the source text answers exactly.
void main() {
  final RegExp registration = RegExp(
    r"""MagicRoute\.page\(\s*'([^']+)'[\s\S]*?\)\.name\('([^']+)'\)""",
  );

  late String source;
  late List<(String path, String name)> routes;

  setUpAll(() {
    source = File('lib/routes/app.dart').readAsStringSync();
    routes = registration
        .allMatches(source)
        .map((m) => (m.group(1)!, m.group(2)!))
        .toList();
  });

  test('the table is read at all, so an empty match cannot pass this file', () {
    // The guard on the guard. A regex that stops matching reports a clean table forever, which is
    // the failure mode `LedgerWritersTest` records for its own detector: a checker whose broken
    // state looks like success is worse than no checker.
    expect(routes.length, greaterThanOrEqualTo(18));
    expect(routes.map((r) => r.$1), contains('/products'));
  });

  test('every path is English, lower-case ASCII', () {
    // The rule this replaced said paths should be Turkish because a URL is user-facing. It is, and
    // that is the argument for English: the primary market is outside Turkey and the default locale
    // is `en`, so a Turkish path is a word the user cannot read in the one place they can copy.
    for (final (String path, String name) in routes) {
      expect(
        RegExp(r'^/[a-z0-9\-/:]*$').hasMatch(path),
        isTrue,
        reason: '$path (registered as $name) is not a lower-case ASCII path',
      );
    }
  });

  test('a path agrees with the name it is registered under', () {
    // The rename was mechanical precisely because the names were already English, so the two now
    // say the same thing and this keeps them saying it. Only the leaf is compared: `/products/new`
    // is `product-create` and `/locations/:id` is `location`, which are deliberate rather than
    // sloppy, so a nested path is exempt from the equality and still checked for its parent.
    for (final (String path, String name) in routes) {
      if (path == '/' || path.split('/').length > 2) continue;

      expect(
        path,
        '/$name',
        reason: 'the path and its route name disagree, which is what the rename existed to end',
      );
    }
  });

  test('a nested path sits under its parent rather than beside it', () {
    final Set<String> paths = routes.map((r) => r.$1).toSet();

    for (final String path in paths) {
      final List<String> segments = path.split('/');

      if (segments.length <= 2) continue;

      final String parent = '/${segments[1]}';

      expect(
        paths,
        contains(parent),
        reason: '$path has no $parent to belong to, so the URL implies a screen that is not there',
      );
    }
  });

  test('the web URL strategy is the path one, which is what makes these addressable', () {
    // Without it every path above renders as `/#/products` and the whole rename buys nothing: the
    // hash is not sent to a server, so the URL is neither shareable in a way anything can read nor
    // reachable on a reload.
    final String config = File('lib/config/routing.dart').readAsStringSync();

    expect(config, contains("'url_strategy': 'path'"));
  });
}
