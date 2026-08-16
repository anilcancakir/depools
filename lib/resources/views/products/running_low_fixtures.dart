import 'product_fixtures.dart';

/// The products a tenant is short of, for the preview catalog and the containment test.
///
/// **This mirrors the server's predicate; it does not define it.** `RunningLowQuery` decides
/// membership for the real screen, because the rule needs the whole tenant's projection, the
/// consumption rate and how often this tenant shops. What lives here is the same rule stated over
/// fixtures, so the catalog draws a realistic screen and `test/running_low_test.dart` has something
/// to assert containment against.
///
/// ### Three ways to be short, and the first is why this is not called `belowTarget`
///
/// It was, and the name encoded a rule that was wrong. A product with nothing on hand is short
/// whether or not anyone ever set a target for it, which matters because the creation form
/// deliberately does not ask: running out needs no threshold to be true. Beyond the target there is
/// also the reorder point the app infers from the consumption rate, which no name mentioning only
/// the target could cover.
///
/// The shopping list is a strict SUPERSET of this: it also carries expiring rows (an opened pot is
/// running out of days, not of quantity) and manual ones, so the containment test asserts one
/// direction and would be asserting something false if it asserted both.
List<ProductListItem> get runningLow => productFixtures
    .where((p) => p.isOut || p.isBelowPar || p.isBelowReorderPoint)
    .toList(growable: false);

/// Products that have run out entirely.
///
/// Their own group at the top, because zero is not a degree of "low": there is nothing left to
/// ration and no decision to make about how soon to act. Same shape as the expired group on the
/// dates screen, for the same reason.
List<ProductListItem> get outOfStock =>
    runningLow.where((p) => p.isOut).toList(growable: false);

/// Short but not empty, in the tier that says how much to trust the ranking.
List<ProductListItem> lowInTier(ForecastTier tier) =>
    runningLow.where((p) => !p.isOut && p.tier == tier).toList(growable: false);
