import 'package:flutter/material.dart';
import 'package:magic/magic.dart';
import 'config/app.dart';
import 'config/routing.dart';
import 'config/view.dart';
import 'config/auth.dart';
import 'config/database.dart';
import 'config/network.dart';
import 'config/cache.dart';
import 'config/logging.dart';
import 'config/broadcasting.dart';
import 'config/deeplink.dart';
import 'config/wind_theme.g.dart';
import 'config/depools_status_tokens.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:magic_devtools/magic_devtools.dart';
import 'package:magic_starter/magic_starter.dart' show MagicStarter;
import 'config/magic_starter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Dev tooling (dusk + telescope) boots BEFORE Magic.init so the snapshot
  // pipeline and exception watchers are live during boot. The kDebugMode guard
  // keeps the whole branch tree-shaken out of release builds. One call replaces
  // the separate DuskPlugin / TelescopePlugin installs. See MagicDevtools.
  if (kDebugMode) MagicDevtools.installPre();

  await Magic.init(
    configFactories: [
      () => appConfig,
      () => routingConfig,
      () => viewConfig,
      () => authConfig,
      () => databaseConfig,
      () => networkConfig,
      () => cacheConfig,
      () => loggingConfig,
      () => broadcastingConfig,
      () => deeplinkConfig,
      () => magicStarterConfig,
    ],
  );

  // Magic integrations wire magic's runtime into dusk + telescope AFTER
  // Magic.init, once the IoC container is populated. See MagicDevtools.
  if (kDebugMode) MagicDevtools.installPost();

  // Theme generated from DESIGN.md via `design:sync`. Regenerate with:
  //   dart run bin/dispatcher.dart design:sync
  //
  // The status aliases are a hand-authored supplement: design:sync only emits the
  // 17 canonical semantic roles, so the inventory status vocabulary
  // (in-stock, expiring, expired, wasted, ai, ...) is merged in on top. It comes
  // second so a status key would win a collision, and there are none today.
  final windTheme = WindThemeData(
    colors: designColors,
    aliases: {...designAliases, ...depoolsStatusAliases},
  );

  // Adopt the wind theme across every magic_starter sub-theme in one call, so
  // the starter's navigation, form, auth, and layout surfaces derive from the
  // same DESIGN.md tokens instead of the starter defaults.
  MagicStarter.useWindTheme(windTheme);

  runApp(MagicApplication(title: 'Depools', windTheme: windTheme));
}
