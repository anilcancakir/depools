import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart';

import '../resources/views/dashboard_view.dart';
import '../resources/views/locations/location_index_view.dart';
import '../resources/views/products/assistant_view.dart';
import '../resources/views/products/barcode_scan_view.dart';
import '../resources/views/products/dates_view.dart';
import '../resources/views/products/product_index_view.dart';
import '../resources/views/products/product_show_view.dart';
import '../resources/views/products/running_low_view.dart';
import '../resources/views/products/shopping_list_view.dart';
import '../resources/views/products/stock_take_view.dart';

/// Application Route Definitions.
///
/// Register all application routes here. This function is called by
/// [RouteServiceProvider.boot()] during the Magic bootstrap lifecycle.
///
/// See also: `lib/app/kernel.dart` for middleware registration.
///
/// ### Every screen that exists is reachable from here (D61)
///
/// Until now this file registered exactly ONE route, `/` to the dashboard, while twelve built
/// screens existed only as entries in the `/preview` catalog. They rendered, they were verified,
/// and the running app could not reach any of them: the sidebar offered Dashboard and Settings,
/// and nothing else was addressable. A screen nobody can navigate to is not shipped, however
/// green its preview is.
///
/// The paths are Turkish and plural, matching the nouns the UI uses, because a URL is user-facing
/// on web and `/urunler` reads as this app's own where `/products` reads as a scaffold's.
///
/// The views still render fixtures rather than controller state. That is the next seam, and
/// routing them first is deliberate: it puts every screen in front of the shell it will actually
/// live in, which is where the header offsets, the bottom nav overlap and the scroll ownership
/// problems surface. None of those are visible in a preview pane.
void registerAppRoutes() {
  // Auth-protected routes with AppLayout
  MagicRoute.group(
    layout: (child) => MagicStarter.view.makeLayout('layout.app', child: child),
    middleware: ['auth'],
    layoutId: 'app',
    routes: () {
      MagicRoute.page('/', () => const DashboardView()).name('dashboard');

      // The three forecasting surfaces, in the order `forecasting.md` ranks them: what is
      // running out of time, what is short, and what to buy.
      MagicRoute.page('/tarihler', () => const DatesView()).name('dates');
      MagicRoute.page('/azalanlar', () => const RunningLowView()).name('running-low');
      MagicRoute.page('/alisveris', () => const ShoppingListView()).name('shopping');

      // Stock itself.
      MagicRoute.page('/urunler', () => const ProductIndexView()).name('products');
      MagicRoute.page('/urunler/:id', () => const ProductShowView()).name('product');
      MagicRoute.page('/konumlar', () => const LocationIndexView()).name('locations');
      MagicRoute.page('/sayim', () => const StockTakeView()).name('stock-take');

      // Capture. The assistant is the sentence path and the scanner is the barcode path; both
      // end in the same pending-change review, so they are peers rather than one inside the other.
      MagicRoute.page('/asistan', () => const AssistantView()).name('assistant');
      MagicRoute.page('/tara', () => const BarcodeScanView()).name('scan');
    },
  );
}
