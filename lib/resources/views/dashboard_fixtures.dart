import '../../app/models/dashboard_summary.dart';
import '../../app/models/movement_entry.dart';
import 'products/expiring_fixtures.dart';
import 'products/product_fixtures.dart';
import 'products/running_low_fixtures.dart';
import 'products/shopping_fixtures.dart';

/// The dashboard's payload, assembled from the fixtures the other screens already use.
///
/// **This is what keeps the preview catalog offline.** The screen reads one `DashboardSummary` from
/// its controller; the catalog hands it the same shape built locally, so `/preview` renders it with
/// no server and no session.
///
/// Composed from the OTHER screens' fixtures rather than invented here, which is the property the
/// screen's own docblock asks for: a dashboard figure has to be the same number the page it links to
/// would show, and two independent fixtures would drift the first time one of them was edited.
DashboardSummary dashboardFixture() {
  final List<DatedLot> expired = expiredRows();
  final List<DatedLot> approaching = approachingByLocation()
      .values
      .expand((List<DatedLot> rows) => rows)
      .toList();

  return DashboardSummary(
    hasStock: true,
    products: productFixtures.length,
    locations: locationOptions.length,
    expiredCount: expired.length,
    approachingCount: approaching.length,
    outOfStockCount: outOfStock.length,
    // The fixture's `runningLow` INCLUDES the out-of-stock rows, and the endpoint's two counters do
    // not overlap, so the preview subtracts to match what the server would answer. Getting this
    // wrong would make the catalog show a total the real screen never produces.
    belowTargetCount: runningLow.where((ProductListItem p) => !p.isOut).length,
    // From the shopping fixture, which is what the card USED to read directly. The number is the
    // same either way; what changed is that the real screen no longer reaches for this file.
    shoppingCount: pendingLines.length,
    expired: expired,
    approaching: approaching,
    outOfStock: outOfStock,
    belowTarget: runningLow.where((ProductListItem p) => !p.isOut).toList(),
    activity: _activity,
  );
}

/// A tenant who has not added anything yet, which is a different SCREEN rather than a thinner one.
DashboardSummary dashboardFreshFixture() {
  return const DashboardSummary(
    hasStock: false,
    products: 0,
    locations: 0,
    expiredCount: 0,
    approachingCount: 0,
    outOfStockCount: 0,
    belowTargetCount: 0,
    shoppingCount: 0,
    expired: <DatedLot>[],
    approaching: <DatedLot>[],
    outOfStock: <ProductListItem>[],
    belowTarget: <ProductListItem>[],
    activity: <MovementEntry>[],
  );
}

/// Three ledger entries spanning products, which is what makes this feed different from a product's.
///
/// Written as `MovementEntry` rather than as sentences, because that is what the endpoint sends: the
/// row composes its own words from the reason and the actor type, so a fixture carrying phrases
/// would be testing different code from the one that runs.
final List<MovementEntry> _activity = <MovementEntry>[
  MovementEntry(
    reason: 'purchase',
    delta: 6,
    actorType: 'user',
    actorName: 'Anıl',
    locationName: 'Kiler › Raf 1',
    productName: 'Pınar Süt Tam Yağlı 1 lt',
    at: DateTime.now().subtract(const Duration(hours: 2)),
  ),
  MovementEntry(
    reason: 'consumption',
    delta: -1,
    actorType: 'assistant',
    locationName: 'Mutfak › Buzdolabı',
    productName: 'Kaşar Peyniri 500 g',
    at: DateTime.now().subtract(const Duration(hours: 5)),
  ),
  MovementEntry(
    reason: 'waste',
    delta: -2,
    actorType: 'user',
    actorName: 'Anıl',
    locationName: 'Mutfak › Buzdolabı',
    productName: 'Marul',
    at: DateTime.now().subtract(const Duration(days: 1)),
  ),
];
