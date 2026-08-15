import 'package:magic/magic.dart';
import 'package:flutter/material.dart';
import 'package:magic_starter/magic_starter.dart';
import '../models/user.dart';
import '../support/icon_catalogue.dart';

/// Application Service Provider.
///
/// Use this provider to bind your own services to the IoC container and
/// to perform any bootstrap logic that requires other services to be ready.
class AppServiceProvider extends ServiceProvider {
  AppServiceProvider(super.app);

  @override
  void register() {
    // The icon catalogue's client-side cache.
    //
    // **A singleton because it IS the cache.** The tree, a location's detail header and the picker
    // all ask for the same handful of names, and three instances would mean three sets of requests
    // for the same glyphs and three copies of the svg in memory. Bound here rather than constructed
    // by the widget that happens to need it first.
    app.singleton('icons', () => IconCatalogue());
  }

  @override
  Future<void> boot() async {
    // Perform async bootstrap logic here.
    //
    // IMPORTANT: Call setUserFactory() so Auth.user<T>() returns your model:
    //   Auth.manager.setUserFactory((data) => User.fromMap(data));
    // Magic Starter: Register user factory for auth session restoration.
    Auth.manager.setUserFactory((data) => User.fromMap(data));

    // Magic Starter: Register the identity contract in one call. The team
    // trio is required here because `magic_starter.features.teams` is true
    // in lib/config/magic_starter.dart; omitting it would throw a StateError.
    MagicStarter.bootstrap(
      userFactory: (data) => User.fromMap(data),
      onLogout: () async {
        await Auth.logout();
        MagicRoute.to(MagicStarterConfig.loginRoute());
      },
      locales: {'tr': 'Türkçe', 'en': 'English'},
      currentTeam: () => User.current.currentTeam?.toMagicStarterTeam(),
      allTeams: () => User.current.allTeams.map((t) => t.toMagicStarterTeam()).toList(),
      onSwitch: (teamId) => MagicStarterTeamController.instance.switchTeam(teamId),
    );

    // Magic Starter: one page geometry for every page, ours and the starter's.
    //
    // Set here rather than per page because MSPageContainer reads exactly one
    // value: a page that carries its own cap disagrees with its neighbours inside
    // the same shell, which is the drift MSPageScaffold's docblock describes.
    //
    // The values follow DESIGN.md's Layout section: `p-4` (16px) edge margins
    // widening to 20px, and `max-w-6xl` (1152px) as the content cap. The cap earns
    // its place on measurement, not on a platform role: a product row stretched
    // across a full desktop window puts the quantity column an eye-movement away
    // from the name it belongs to. 6xl keeps a long list scannable while still
    // showing more rows than a narrow window does.
    MagicStarter.manager.pageContainerClassName = 'max-w-6xl px-4 md:px-5 pt-6 pb-16';

    // Magic Starter: Navigation items for sidebar and mobile bottom bar.
    //
    // It offered Dashboard and Settings while twelve built screens sat unreachable in the preview
    // catalog. `lib/routes/app.dart` now registers them; this is what makes them findable.
    //
    // **The labels are Turkish inside `en.json`, and that is a transitional state, not a mistake.**
    // magic's `Translator` REPLACES its sentence map per locale instead of merging with the
    // fallback, so a partial `tr.json` renders raw keys (`auth.login_title`) on every screen it
    // does not cover. Until a complete `tr.json` lands, `en.json` is this app's only catalogue and
    // its single user-facing language is Turkish, so the product vocabulary goes there.
    //
    // The bottom bar carries five, which is the ceiling before a mobile tab bar starts truncating
    // labels. Which five is a claim about a phone in a stockroom: read what is urgent, capture what
    // just arrived, look something up. Sayım and Konumlar are desk work and stay in the sidebar.
    MagicStarter.useNavigation(
      mainItems: [
        MagicStarterNavItem(
          icon: Icons.dashboard_outlined,
          labelKey: 'nav.dashboard',
          path: MagicStarterConfig.homeRoute(),
        ),
        MagicStarterNavItem(
          icon: Icons.event_outlined,
          labelKey: 'nav.dates',
          path: '/dates',
        ),
        MagicStarterNavItem(
          icon: Icons.trending_down_outlined,
          labelKey: 'nav.running_low',
          path: '/running-low',
        ),
        MagicStarterNavItem(
          icon: Icons.shopping_cart_outlined,
          labelKey: 'nav.shopping',
          path: '/shopping',
        ),
        MagicStarterNavItem(
          icon: Icons.inventory_2_outlined,
          labelKey: 'nav.products',
          path: '/products',
        ),
        // Search is a destination rather than a field on one list, because it answers across
        // products AND locations and neither list can host the other's results.
        MagicStarterNavItem(
          icon: Icons.search_outlined,
          labelKey: 'nav.search',
          path: '/search',
        ),
        MagicStarterNavItem(
          icon: Icons.warehouse_outlined,
          labelKey: 'nav.locations',
          path: '/locations',
        ),
        MagicStarterNavItem(
          icon: Icons.checklist_outlined,
          labelKey: 'nav.stock_take',
          path: '/stock-take',
        ),
        MagicStarterNavItem(
          icon: Icons.auto_awesome_outlined,
          labelKey: 'nav.assistant',
          path: '/assistant',
        ),
        // This app's own settings, not the starter's profile screen: the two preferences D66 and
        // D67 created live here, and the account settings are one tap further in.
        MagicStarterNavItem(
          icon: Icons.settings_outlined,
          labelKey: 'nav.settings',
          path: '/settings',
        ),
      ],
      bottomItems: [
        MagicStarterNavItem(
          icon: Icons.dashboard_outlined,
          labelKey: 'nav.dashboard',
          path: MagicStarterConfig.homeRoute(),
        ),
        MagicStarterNavItem(
          icon: Icons.event_outlined,
          labelKey: 'nav.dates',
          path: '/dates',
        ),
        MagicStarterNavItem(
          icon: Icons.qr_code_scanner_outlined,
          labelKey: 'nav.scan',
          path: '/scan',
        ),
        MagicStarterNavItem(
          icon: Icons.shopping_cart_outlined,
          labelKey: 'nav.shopping',
          path: '/shopping',
        ),
        MagicStarterNavItem(
          icon: Icons.inventory_2_outlined,
          labelKey: 'nav.products',
          path: '/products',
        ),
        // Search is a destination rather than a field on one list, because it answers across
        // products AND locations and neither list can host the other's results.
        MagicStarterNavItem(
          icon: Icons.search_outlined,
          labelKey: 'nav.search',
          path: '/search',
        ),
      ],
    );

    // Magic Starter: reset every session-scoped controller (polling,
    // realtime, cached lists) on login and team switch. Registered last so
    // the identity contract and navigation above already point at the new
    // session before SessionScopeSync refetches its data; registering it
    // earlier would refetch against the previous tenant's resolver. Without
    // this, magic's Type-keyed singleton controllers keep the previous
    // tenant's rows on screen after a re-login or team switch.
    SessionScopeSync.attach();
  }
}
