import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart';

import '../ui/components/assistant_launcher/assistant_launcher.dart';
import '../resources/views/dashboard_view.dart';
import '../resources/views/locations/location_index_view.dart';
import '../resources/views/settings_view.dart';
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
    // The assistant wraps the SHELL rather than each route, which is what makes it persistent
    // (D67).
    //
    // **Outside the layout, not inside it, and the first version had it the wrong way round.**
    // Wrapping the route's child put the `Positioned` inside the shell's scroll view, so it
    // anchored to the bottom of the SCROLLED CONTENT rather than to the viewport and sat far below
    // the fold. It rendered nothing and threw nothing, which is the worst combination: the widget
    // was building correctly the whole time.
    //
    // Outside, it floats over the navigation as well, which the launcher's own bottom inset is
    // there to clear. A control that covers a tab steals taps from it.
    layout: (child) => AssistantLauncher(
      child: MagicStarter.view.makeLayout('layout.app', child: child),
    ),
    middleware: ['auth'],
    // **No shared `layoutId`, and that is what makes the wrapper above run at all.**
    // magic merges layouts by id and the FIRST builder wins (`magic_router.dart`
    // `_mergeLayouts`). `magic_starter` registers `'app'` before this file does, so a builder
    // here was collected and then discarded: the launcher built correctly and was never in the
    // tree, with nothing logged. Dropping the id gives this group its own shell.
    //
    // The cost is that these routes no longer share a shell instance with the starter's own
    // screens, so shell state is rebuilt when crossing between them. That is acceptable: the
    // crossing is rare (settings, profile) and the shell holds no state worth preserving.
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

      // Capture. The scanner is the barcode path; the assistant is the sentence path and is
      // registered separately below, because it takes over the screen.
      MagicRoute.page('/tara', () => const BarcodeScanView()).name('scan');

      // This app's own settings, distinct from the account settings `magic_starter` owns. It
      // holds the two preferences D66 and D67 created and had nowhere to live.
      MagicRoute.page('/ayarlar', () => const SettingsView()).name('settings');
    },
  );

  // **The assistant is outside the shell, and that is what makes it a chat window.**
  //
  // Anılcan: on a phone it should hide the bottom menu and be a full chat window, like WhatsApp or
  // ChatGPT. Those apps do not put a conversation in a tab; entering one is a push that takes over
  // the display, and leaving it is a back gesture. Rendering it inside the shell put a navigation
  // bar under the composer and made the whole page scroll, so the composer moved with the content
  // instead of staying where a thumb expects it.
  //
  // Outside the shell there is no bottom bar to work around and no ambient scroll, which is also
  // why the transcript could drop the computed height it used to carry. The screen provides its own
  // way back through the header.
  //
  // The floating assistant launcher is attached to the shell group, so it correctly does not appear
  // here: a button to the screen you are already on is noise.
  MagicRoute.group(
    middleware: ['auth'],
    routes: () {
      MagicRoute.page('/asistan', () => const AssistantView()).name('assistant');
    },
  );
}
