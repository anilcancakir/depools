import 'package:magic/magic.dart';
import 'package:flutter/material.dart';
import 'package:magic_starter/magic_starter.dart';
import '../models/user.dart';

/// Application Service Provider.
///
/// Use this provider to bind your own services to the IoC container and
/// to perform any bootstrap logic that requires other services to be ready.
class AppServiceProvider extends ServiceProvider {
  AppServiceProvider(super.app);

  @override
  void register() {
    // Bind your services here (sync only, do not resolve other services).
    // Example:
    //   app.singleton('my_service', () => MyService());
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
      locales: {'en': 'English'},
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
    MagicStarter.useNavigation(
      mainItems: [
        MagicStarterNavItem(
          icon: Icons.dashboard_outlined,
          labelKey: 'nav.dashboard',
          path: MagicStarterConfig.homeRoute(),
        ),
        MagicStarterNavItem(
          icon: Icons.settings_outlined,
          labelKey: 'nav.settings',
          path: MagicStarterConfig.profileRoute(),
        ),
      ],
      bottomItems: [
        MagicStarterNavItem(
          icon: Icons.dashboard_outlined,
          labelKey: 'nav.dashboard',
          path: MagicStarterConfig.homeRoute(),
        ),
        MagicStarterNavItem(
          icon: Icons.settings_outlined,
          labelKey: 'nav.settings',
          path: MagicStarterConfig.profileRoute(),
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
