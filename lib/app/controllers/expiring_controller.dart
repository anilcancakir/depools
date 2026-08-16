import 'package:magic/magic.dart';

import '../../resources/views/products/expiring_fixtures.dart';
import '../support/mapped_or_null.dart';

/// What is running out of time, from `api/v1/expiring`.
///
/// ### The horizon is a request, not a filter
///
/// The screen's chips change what the SERVER is asked for rather than narrowing a list already
/// held, because the widest chip is 30 days and holding a month of lots to show three days of them
/// is the wrong trade for a phone. Each chip is one request, and the answer is cached per horizon so
/// tapping back and forth does not refetch.
///
/// ### Two shapes, one list
///
/// A lot and a serial unit's warranty arrive as the same row with a different `kind`, because the
/// screen treats them the same way: a thing, a date, a place. The grouping below does not look at
/// the kind at all.
class ExpiringController extends MagicController with MagicStateMixin<List<DatedLot>> {
  /// The shared instance, keyed by type.
  static ExpiringController get instance => Magic.findOrPut(ExpiringController.new);

  /// What each horizon answered, so a chip already visited draws immediately.
  ///
  /// Small by construction: three chips, and the answer for each is a screenful.
  final Map<int, List<DatedLot>> _held = <int, List<DatedLot>>{};

  int _horizon = defaultHorizonDays;

  /// The horizon currently being shown.
  int get horizon => _horizon;

  /// The rows for the horizon being shown, or empty while it is in flight.
  List<DatedLot> get rows => rxState ?? const <DatedLot>[];

  /// Whether anything has been fetched at all, as opposed to fetched and empty.
  ///
  /// An empty list is the GOOD outcome on this screen, so it has to be told apart from a fetch that
  /// has not answered: the empty state reads "nothing is running out", which is a lie while the
  /// request is still in flight.
  bool get loaded => _held.containsKey(_horizon);

  @override
  void onInit() {
    super.onInit();
    load();
  }

  /// Show a horizon, fetching it the first time.
  Future<void> load({int? horizon, bool force = false}) async {
    final int days = horizon ?? _horizon;

    _horizon = days;

    final List<DatedLot>? held = _held[days];

    if (held != null && !force) {
      setSuccess(held);

      return;
    }

    setLoading();

    final dynamic response = await Http.get('/expiring?horizon=$days');

    if (!response.successful) {
      setError(response.message ?? Lang.get('screens.dates.load_failed'));

      return;
    }

    final List<DatedLot>? rows = mappedOrNull<List<DatedLot>?>(
      () {
        final Object? data = response['data'];

        if (data is! List) return null;

        final List<DatedLot> found = <DatedLot>[];

        for (final Object? row in data) {
          if (row is! Map<String, dynamic>) return null;

          final DatedLot? lot = DatedLot.fromApi(row);

          // **One unreadable row fails the fetch.** This screen exists to be exhaustive: a user who
          // reads it and finds nothing concludes nothing is going off. A row silently dropped from
          // that list is worse than an error message.
          if (lot == null) return null;

          found.add(lot);
        }

        return found;
      },
      describing: 'the expiring list',
    );

    if (rows == null) {
      setError(Lang.get('screens.dates.load_failed'));

      return;
    }

    // Only after the horizon is still the one asked for. A slower request for 30 days must not
    // overwrite the 3-day answer the user is now looking at.
    if (_horizon != days) return;

    _held[days] = rows;

    setSuccess(rows);
  }
}
