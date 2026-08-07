import 'package:flutter/foundation.dart';

import 'product_filter_sheet.dart' show FilterOption;
import 'product_fixtures.dart';

/// One lot that needs attention, with the product it belongs to.
@immutable
class ExpiringLot {
  /// The product the lot belongs to.
  final ProductListItem product;

  /// The lot itself.
  final LotFixture lot;

  /// Creates an [ExpiringLot].
  const ExpiringLot({required this.product, required this.lot});

  /// Whether the date has already passed.
  bool get isExpired => (lot.daysUntilExpiry ?? 0) < 0;
}

/// Every lot inside its own product's window, or already past its date.
///
/// **The row is a LOT, not a product**, which is the whole difference between this screen
/// and the stock list. A product with three cartons has three dates and only the oldest one
/// is a problem; showing the product would tell a user something needs using without telling
/// them which one to reach for. `forecasting.md` says it plainly: this is a date comparison
/// over lots.
///
/// **The window is the product's own, not a global number of days** (D55). The doc's
/// summary says "what expires in the next N days", and D24 already settled that a single N
/// cannot serve both a five-day milk and a one-year flour: the threshold is the last fifth
/// of a product's shelf life, floored at one day and capped at sixty. So a carton of milk
/// enters this list at one day out and a sack of flour at seventy-three, and both are
/// equally urgent for their own kind.
///
/// Derived from `productFixtures`, so a lot cannot appear here with a date the product page
/// disagrees about.
List<ExpiringLot> get expiringLots {
  final List<ExpiringLot> found = <ExpiringLot>[];

  for (final ProductListItem product in productFixtures) {
    for (final LotFixture lot in product.lots) {
      final int? days = lot.daysUntilExpiry;
      if (lot.isDepleted || days == null) continue;
      if (days <= product.expiryThresholdDays) {
        found.add(ExpiringLot(product: product, lot: lot));
      }
    }
  }

  // Soonest first, expired at the very top since those are already past being a warning.
  found.sort((a, b) => (a.lot.daysUntilExpiry ?? 0).compareTo(b.lot.daysUntilExpiry ?? 0));
  return found;
}

/// Lots already past their date. Their own group, because this is a decision rather than a
/// warning: the stock either gets used anyway or written off.
List<ExpiringLot> get expiredLots => expiringLots.where((e) => e.isExpired).toList();

/// Lots approaching their date, still good.
List<ExpiringLot> get approachingLots => expiringLots.where((e) => !e.isExpired).toList();

/// The approaching lots grouped by where they are, in the order the locations read.
///
/// `forecasting.md` asks for this per location and the use case is why: a cafe's morning
/// check is a walk to the fridge, then the freezer, then the dry store. Grouping by location
/// matches the walk; sorting by urgency inside a group matches what to pick up first.
Map<String, List<ExpiringLot>> get approachingByLocation {
  final Map<String, List<ExpiringLot>> grouped = <String, List<ExpiringLot>>{};

  for (final FilterOption option in locationOptions) {
    final List<ExpiringLot> here = approachingLots
        .where((e) => e.lot.locationId == option.id)
        .toList();
    if (here.isNotEmpty) grouped[option.fullPath] = here;
  }

  return grouped;
}
