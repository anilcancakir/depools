import 'package:magic/magic.dart';

import '../models/dashboard_summary.dart';
import '../models/location_node.dart';
import '../support/mapped_or_null.dart';
import 'location_controller.dart';

/// The landing screen, from `api/v1/dashboard`.
///
/// ### One request, and the screen's own rule is why
///
/// `DashboardView` says no figure on it may disagree with the page it links to. Four calls would each
/// arrive at their own moment, giving four loading states and a subtitle that lands last, and two of
/// them could be computed either side of midnight.
///
/// ### Refetched on return, unlike every other screen here
///
/// The other controllers guard against refetching, because a product or a location changes a few
/// times a month. This one is the opposite: a user comes BACK to it after doing the thing it told
/// them to do, and a cached "1 expired" after they have just thrown that carton away is the screen
/// contradicting itself. So [load] re-asks by default and the held copy is only the thing drawn
/// while the answer is in flight.
class DashboardController extends MagicController with MagicStateMixin<DashboardSummary> {
  /// The shared instance, keyed by type.
  static DashboardController get instance => Magic.findOrPut(DashboardController.new);

  bool _loaded = false;

  /// The summary, or null before the first answer.
  DashboardSummary? get summary => rxState;

  /// Whether anything has been fetched at all.
  ///
  /// The screen has TWO shapes and the flag decides which, so it cannot be guessed from an empty
  /// summary: a fresh tenant gets the setup steps, and showing those to somebody with forty products
  /// while their dashboard is still loading is the worst version of this screen.
  bool get loaded => _loaded;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  /// Fetch the screen.
  ///
  /// [quiet] keeps the current copy on screen while re-asking, for the revisit case: replacing a
  /// drawn dashboard with skeletons every time the user comes back would make the app feel like it
  /// forgets where they were.
  Future<void> load({bool quiet = false}) async {
    if (!quiet || !_loaded) setLoading();

    final dynamic response = await Http.get('/dashboard');

    if (!response.successful) {
      setError(response.message ?? Lang.get('screens.dashboard.load_failed'));

      return;
    }

    // **The location names come from the tree**, because a product row names the places it sits in
    // and the payload carries ids. The tree is a singleton the shell loads anyway; an empty map is
    // survivable here, since a dashboard row shows a product rather than a place.
    final Map<String, String> labels = <String, String>{
      for (final LocationNode node in LocationController.instance.nodes)
        if (node.id != null) node.id!: node.path,
    };

    final DashboardSummary? summary = mappedOrNull<DashboardSummary?>(
      () {
        final Object? data = response['data'];

        return data is Map<String, dynamic>
            ? DashboardSummary.fromApi(data, locationLabels: labels)
            : null;
      },
      describing: 'the dashboard',
    );

    if (summary == null) {
      setError(Lang.get('screens.dashboard.load_failed'));

      return;
    }

    _loaded = true;

    setSuccess(summary);
  }
}
