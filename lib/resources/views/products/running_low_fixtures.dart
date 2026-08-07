import 'product_fixtures.dart';

/// Products whose stock is under the target the user set.
///
/// **One predicate, read by two screens.** The shopping list and this list must never
/// disagree about which products are short, so the membership test lives here and
/// `test/running_low_test.dart` asserts that every product it returns also appears on the
/// shopping list. A comment would not have caught a drift; a test does.
///
/// The reverse containment deliberately does NOT hold. The shopping list is
/// below-target UNION expiring UNION manual, so it is a superset: the yoghurt is on it
/// because an opened pot is running out of days, and the washing-up liquid because someone
/// typed it. Asserting equality would be asserting something false.
List<ProductListItem> get belowTarget => productFixtures
    .where((p) => p.parLevel != null && p.amount < p.parLevel!)
    .toList(growable: false);

/// Products that have run out entirely.
///
/// Their own group at the top, because zero is not a degree of "low": there is nothing left
/// to ration and no decision to make about how soon to act. Same shape as the expired group
/// on the dates screen, for the same reason.
List<ProductListItem> get outOfStock => belowTarget.where((p) => p.isOut).toList();

/// Short but not empty, in the tier that says how much to trust the ranking.
List<ProductListItem> lowInTier(ForecastTier tier) =>
    belowTarget.where((p) => !p.isOut && p.tier == tier).toList();
