import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Whether this app's own routes collide with the ones `magic_starter` registers.
///
/// **`RouteServiceProvider.boot` registers the starter's routes first, so a shared path means the
/// starter wins and this app's screen is never built.** It happened on `/settings`: the config
/// shipped `'profile_prefix': '/settings'` and `lib/routes/app.dart` registered `/settings` for
/// `SettingsView`, so the navigation item labelled Settings opened the account screen. The three
/// preferences that live there were unreachable, and so were `/plan` and `/mcp`, whose only entry
/// point is that screen.
///
/// Nothing else could see it. Both registrations are valid, the app navigates without complaint,
/// and the screen that renders is a real screen: the only symptom is a screen that never appears.
///
/// Read from source rather than from a booted router, for the reason `route_paths_test` gives: the
/// prefixes are config literals and the paths are string arguments, so the text answers the
/// question exactly and a container does not have to be stood up to ask it.
void main() {
  late Set<String> appPaths;
  late Map<String, String> starterPrefixes;

  setUpAll(() {
    final RegExp registration = RegExp(r"""MagicRoute\.page\(\s*'([^']+)'""");
    appPaths = registration
        .allMatches(File('lib/routes/app.dart').readAsStringSync())
        .map((RegExpMatch m) => m.group(1)!)
        .toSet();

    final RegExp prefix = RegExp(r"""'(\w+_prefix|home|login)':\s*'([^']+)'""");
    starterPrefixes = <String, String>{
      for (final RegExpMatch m
          in prefix.allMatches(File('lib/config/magic_starter.dart').readAsStringSync()))
        m.group(1)!: m.group(2)!,
    };
  });

  test('both sides are read at all, so an empty match cannot pass this file', () {
    // The guard on the guard: two regexes that stop matching agree perfectly about nothing.
    expect(appPaths.length, greaterThanOrEqualTo(18));
    expect(starterPrefixes.keys, containsAll(<String>['profile_prefix', 'teams_prefix']));
  });

  test('no screen of this app sits on a route the starter already owns', () {
    // `home` is excluded: `/` is the starter's home AND this app's dashboard by design, and the
    // starter registers no page there, it only navigates to it.
    final Map<String, String> collisions = <String, String>{
      for (final MapEntry<String, String> entry in starterPrefixes.entries)
        if (entry.key != 'home' && appPaths.contains(entry.value)) entry.key: entry.value,
    };

    expect(
      collisions,
      isEmpty,
      reason: collisions.entries
          .map((e) => 'magic_starter ${e.key} is ${e.value}, which lib/routes/app.dart also claims')
          .join('\n'),
    );
  });
}
