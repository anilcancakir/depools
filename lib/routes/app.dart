import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart';

import '../ui/layouts/assistant_launcher.dart';
import '../ui/layouts/page_chrome.dart';
import '../resources/views/dashboard_view.dart';
import '../resources/views/locations/location_form_view.dart';
import '../resources/views/locations/location_index_view.dart';
import '../resources/views/locations/location_show_view.dart';
import '../resources/views/mcp_access_view.dart';
import '../resources/views/plan_view.dart';
import '../resources/views/search_view.dart';
import '../resources/views/settings_view.dart';
import '../resources/views/products/assistant_view.dart';
import '../resources/views/products/barcode_scan_view.dart';
import '../resources/views/products/label_print_view.dart';
import '../resources/views/products/product_draft_view.dart';
import '../resources/views/products/receipt_review_view.dart';
import '../resources/views/products/shelf_photo_view.dart';
import '../resources/views/products/dates_view.dart';
import '../resources/views/products/product_form_view.dart';
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
    // **Both wrappers go OUTSIDE the layout, and that is the whole reason they work.**
    //
    // The shell puts every route inside `WDiv(className: 'flex-1 overflow-y-auto')`, so anything
    // mounted from a page is handed unbounded height and anchors to the bottom of the SCROLLED
    // CONTENT rather than to the viewport. The first assistant launcher wrapped the route's child
    // and sat far below the fold: it rendered nothing and threw nothing, which is the worst
    // combination, because the widget was building correctly the whole time. Out here the box is
    // the window, so a `Stack` can anchor to it, and both wrappers paint over the navigation as
    // well. `ui/layouts/page_chrome.dart` carries the longer version.
    //
    // **The order between them is load-bearing.** The host folds the pinned footer's measured
    // height into `MediaQuery.padding.bottom` for everything below it, and the launcher already
    // reads that padding to clear the navigation bar. Nested inside, the floating button lifts by
    // exactly the footer's height and needs to know nothing about footers. Outside, it would not
    // see the injected padding and would land on top of the footer, which is what it did.
    layout: (child) => PageChromeHost(
      child: AssistantLauncher(
        child: MagicStarter.view.makeLayout('layout.app', child: child),
      ),
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
      // **Before `:id`, and the order is load-bearing.** A path parameter matches any segment, so
      // registering the literal second would send `/urunler/yeni` to the detail screen looking for
      // a product whose id is the word "yeni".
      MagicRoute.page('/urunler/yeni', () => const ProductFormView()).name('product-create');
      MagicRoute.page('/urunler/:id', () => const ProductShowView()).name('product');
      MagicRoute.page('/konumlar', () => const LocationIndexView()).name('locations');
      // Literal before the parameter, for the reason `/urunler/yeni` states.
      MagicRoute.page('/konumlar/yeni', () => const LocationFormView()).name('location-create');
      MagicRoute.page('/konumlar/:id', () => LocationShowView()).name('location');
      MagicRoute.page('/sayim', () => const StockTakeView()).name('stock-take');

      // Capture. The scanner is the barcode path; the assistant is the sentence path and is
      // registered separately below, because it takes over the screen.
      MagicRoute.page('/tara', () => const BarcodeScanView()).name('scan');

      // **The four screens D61 would have caught again.** These were built, previewed and
      // verified, and the running app could reach none of them: no route, and no other screen
      // linked to them. A screen nobody can navigate to is not shipped, and the point of routing
      // them during the design phase is that the FLOW becomes walkable rather than the screens
      // becoming individually viewable.
      //
      // Each is reachable from where it belongs rather than from a menu of everything: the draft
      // from a scan the cascade could not resolve, the receipt and the shelf photo from the
      // overview's capture actions, the label sheet from the product it labels.
      MagicRoute.page('/taslak', () => const ProductDraftView()).name('draft');
      MagicRoute.page('/fis', () => const ReceiptReviewView()).name('receipt');
      MagicRoute.page('/raf', () => const ShelfPhotoView()).name('shelf-photo');
      MagicRoute.page('/etiket', () => const LabelPrintView()).name('labels');

      // This app's own settings, distinct from the account settings `magic_starter` owns. It
      // holds the two preferences D66 and D67 created and had nowhere to live.
      // One search over everything, because four dead per-list fields could not answer what
      // `iterations.md` asks of v1: a location is not findable from the product list.
      MagicRoute.page('/ara', () => const SearchView()).name('search');

      MagicRoute.page('/ayarlar', () => const SettingsView()).name('settings');

      // The two v1 surfaces that had no screen at all. Both are reached from settings, which is
      // where a user looks for anything they can change, and both are screens rather than settings
      // sections because each carries a list and actions rather than one value.
      MagicRoute.page('/plan', () => const PlanView()).name('plan');
      MagicRoute.page('/mcp', () => const McpAccessView()).name('mcp');
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
