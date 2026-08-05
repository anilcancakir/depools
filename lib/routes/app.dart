import 'package:magic/magic.dart';

// import '../resources/views/welcome_view.dart'; // Replaced by DashboardView
import 'package:magic_starter/magic_starter.dart';
import '../resources/views/dashboard_view.dart';

/// Application Route Definitions.
///
/// Register all application routes here. This function is called by
/// [RouteServiceProvider.boot()] during the Magic bootstrap lifecycle.
///
/// See also: `lib/app/kernel.dart` for middleware registration.
void registerAppRoutes() {
  // Auth-protected routes with AppLayout
  MagicRoute.group(
    layout: (child) => MagicStarter.view.makeLayout('layout.app', child: child),
    middleware: ['auth'],
    layoutId: 'app',
    routes: () {
      MagicRoute.page('/', () => const DashboardView());
    },
  );

  // MagicRoute.page('/', () => const WelcomeView()).title('Welcome'); // Replaced by DashboardView
}
