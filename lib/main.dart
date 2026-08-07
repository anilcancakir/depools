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
import 'config/depools_paper_tokens.dart';
import 'config/depools_status_tokens.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:magic_devtools/magic_devtools.dart';
import 'package:magic_starter/magic_starter.dart'
    show MagicStarter, MagicStarterCardTheme, MagicStarterPageHeaderTheme;
import 'config/localization.dart';
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
      () => localizationConfig,
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
  //
  // The paper aliases are a second supplement and a different KIND of token: each
  // one holds the same hex on both sides of its `dark:` pair, because they render
  // a picture of paper rather than a surface the app is read on. A printed sheet
  // is white in dark mode too. See lib/config/depools_paper_tokens.dart.
  //
  // fontFamilies binds the two bundled families to Wind's `font-sans` and
  // `font-mono` utilities. `sans` also becomes the Material text theme default,
  // so Inter applies without every widget asking for it; `font-mono` is reached
  // for explicitly on quantities and codes.
  final windTheme = WindThemeData(
    colors: designColors,
    aliases: {...designAliases, ...depoolsStatusAliases, ...depoolsPaperAliases},
    fontFamilies: const {'sans': 'Inter', 'mono': 'Geist Mono'},
  );

  // Adopt the wind theme across every magic_starter sub-theme in one call, so
  // the starter's navigation, form, auth, and layout surfaces derive from the
  // same DESIGN.md tokens instead of the starter defaults.
  MagicStarter.useWindTheme(windTheme);

  // Two starter surfaces need correcting AFTER `useWindTheme`, and the ordering is the whole
  // point: `Magic.init` above boots the service providers, so an override written in
  // `AppServiceProvider.boot` runs BEFORE this line and `fromWind` then overwrites it. Both of
  // these lived there first and were dead code, which cost a round of measurements that looked
  // like the fix had landed. Anything that tunes a `MagicStarterTheme` sub-struct belongs here.

  // Magic Starter: the page header, on this app's tokens and this app's geometry.
  //
  // Two measured defects in the starter's default, both app-wide rather than
  // per page, and both invisible until the header sat next to a card.
  //
  // 1. `p-2 lg:p-4` added a SECOND edge margin on top of the container's own,
  //    so the title started 16px inside every card edge below it while the two
  //    right edges disagreed by the same amount. Measured on the assistant at
  //    1400px: header content 309..1315, card 293..1331. The container owns the
  //    edge margin, so the header keeps only its vertical rhythm.
  //
  // 2. `border-gray-200 dark:border-gray-700` is a raw palette pair, which
  //    DESIGN.md's token-only rule forbids and `bin/design-tokens` cannot catch
  //    because the hex never appears in this repository. `border-color-border`
  //    is the alias for exactly this hairline.
  //
  // `pb-4` under the divider is the third fix: the chips below it were sitting
  // on the rule with nothing between them.
  MagicStarter.usePageHeaderTheme(
    const MagicStarterPageHeaderTheme(
      containerClassName:
          'w-full flex flex-col sm:flex-row items-start sm:items-center '
          'sm:justify-between gap-4 pb-4 border-b border-color-border',
      containerInlineClassName:
          'w-full flex flex-row items-center justify-between gap-4 pb-4 '
          'border-b border-color-border',
      titleClassName: 'text-2xl font-semibold text-fg line-clamp-2',
      subtitleClassName: 'text-sm text-fg-muted line-clamp-2',
    ),
  );

  // Magic Starter: the card tones, because `MagicStarterTheme.fromWind` swaps two of them.
  //
  // `main.dart` calls `useWindTheme` with this app's full alias map, and `fromWind` then maps
  // every starter surface off it. For cards it maps by NAME rather than by ROLE, and the two
  // vocabularies disagree on one word:
  //
  //   fromWind:  surfaceClassName -> bg-surface              insetClassName -> bg-surface-container
  //   shipped:   surfaceClassName -> bg-white (a CARD)       insetClassName -> bg-gray-50 (RECESSED)
  //
  // magic_starter's "surface" variant means "a plain card"; DESIGN.md's `bg-surface` means the
  // PAGE. So the default card variant paints the page colour and an inset panel paints lighter
  // than the card containing it: the ladder runs backwards.
  //
  // Measured on the profile screen in light mode: page `#F3F2F8`, `MSCard` fill `#F3F2F8`,
  // identical, so every card on every starter screen was carried by its hairline alone while
  // this app's own `SectionCard` sat at `#FFFFFF` beside it.
  //
  // Fixed app-side because the starter is a separate repository; the upstream `fromWind`
  // mapping needs its own PR. Ordering is what makes this work: `useWindTheme` runs in `main`
  // before `runApp`, and a provider boots inside it, so these overrides land last.
  MagicStarter.useCardTheme(
    const MagicStarterCardTheme(
      // A card is card tone. `shadow-*` stays off it: DESIGN.md reserves elevation for things
      // that genuinely float, and a card already distinguished by its fill is not one.
      surfaceClassName: 'bg-surface-container border border-color-border',
      // Nested inside a card, so one step further up the ladder, which is DESIGN.md's own
      // `surface` -> `surface-container` -> `surface-container-high` progression.
      insetClassName: 'bg-surface-container-high border border-color-border',
      elevatedClassName: 'bg-surface-container shadow-md',
      titleClassName: 'text-lg font-semibold text-fg',
    ),
  );

  runApp(MagicApplication(title: 'Depools', windTheme: windTheme));
}
