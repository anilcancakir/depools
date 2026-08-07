import 'package:flutter/foundation.dart';

import 'product_filter_sheet.dart' show FilterOption;
import 'product_fixtures.dart';

/// One dated thing that needs attention: a lot, or a product that has only one date.
@immutable
class DatedLot {
  /// The product it belongs to. The row leads with this, because the list spans products.
  final String productName;

  /// The already-localised label, which says what KIND of date this is: `2 gün`,
  /// `Açık · 2 gün`, `Garanti · 2 gün`, `Süresi geçti`.
  final String label;

  /// Days remaining. Negative means the date has passed.
  final int daysUntilExpiry;

  /// The raw remaining quantity, for the zero treatment.
  final num remaining;

  /// The already-formatted quantity.
  final String formatted;

  /// The unit.
  final String unit;

  /// Whether the unit has been opened, which shortens its clock.
  final bool isOpen;

  /// The already-localised opening or arrival line.
  final String? receivedLabel;

  /// The lot code, when there is one.
  final String? lotCode;

  /// Where it is.
  final String locationId;

  /// Creates a [DatedLot].
  const DatedLot({
    required this.productName,
    required this.label,
    required this.daysUntilExpiry,
    required this.remaining,
    required this.formatted,
    required this.unit,
    required this.locationId,
    this.isOpen = false,
    this.receivedLabel,
    this.lotCode,
  });

  /// Whether the date has already passed.
  bool get isExpired => daysUntilExpiry < 0;
}

/// How far ahead the screen looks. The default that other horizons are offered against.
const int defaultHorizonDays = 7;

/// Every dated thing inside [horizonDays], plus everything already past its date.
///
/// **The row is the finest-grained thing that HAS a date, and it is always rendered as a
/// lot.** A product with a lot breakdown contributes one row per lot, because a carton
/// expiring on Tuesday and one expiring next month are two different decisions and showing
/// the product would tell a user something needs using without telling them which one to
/// reach for. A product with no breakdown carries a single date, so it contributes one row:
/// its implicit lot. One row type, no exceptions, and `forecasting.md`'s "a date comparison
/// over lots" holds literally.
///
/// **The horizon is absolute, and that is a correction to an earlier draft of this file**
/// (D55). The first version filtered on each product's own D24 window, reasoning that a
/// single N cannot serve a five-day milk and a one-year flour. Measuring it produced ZERO
/// rows: D24's window for a five-day product is one day, so a carton with two days left was
/// excluded from the one screen built to find it.
///
/// The two things do different jobs. D24's per-product window decides what earns a badge
/// UNPROMPTED, on a screen the user did not open to ask about dates. This screen IS the
/// question "what is coming up", so its scope is a time horizon the user controls, and the
/// urgency inside it is carried by `ExpiryBadge`, which already has a tuned threshold of its
/// own.
///
/// **Not only food.** A warranty ending in two days sits in this list next to a cheese that
/// went off yesterday, and the label says which is which (`Garanti · 2 gün`). Depools is not
/// a pantry app; a screen that filtered warranties out would be one more place the food
/// assumption got baked in.
List<DatedLot> datedLots({int horizonDays = defaultHorizonDays}) {
  final List<DatedLot> found = <DatedLot>[];

  for (final ProductListItem product in productFixtures) {
    if (product.lots.isEmpty) {
      // No breakdown: the product's own date is its single implicit lot.
      final int? days = product.daysUntilExpiry;
      final String? label = product.expiryLabel;
      if (days == null || label == null || product.locationIds.isEmpty) continue;
      if (days > horizonDays) continue;

      found.add(
        DatedLot(
          productName: product.name,
          label: label,
          daysUntilExpiry: days,
          remaining: product.amount,
          formatted: product.formatted,
          unit: product.unit,
          locationId: product.locationIds.first,
        ),
      );
      continue;
    }

    for (final LotFixture lot in product.lots) {
      final int? days = lot.daysUntilExpiry;
      // A depleted lot has nothing left to save, so it is history rather than a task.
      if (lot.isDepleted || days == null || lot.expiryLabel == null) continue;
      if (days > horizonDays) continue;

      found.add(
        DatedLot(
          productName: product.name,
          label: lot.expiryLabel!,
          daysUntilExpiry: days,
          remaining: lot.remaining,
          formatted: lot.formatted,
          unit: lot.unit,
          isOpen: lot.isOpen,
          receivedLabel: lot.isOpen ? lot.openedLabel : lot.receivedLabel,
          lotCode: lot.lotCode,
          locationId: lot.locationId,
        ),
      );
    }
  }

  found.sort((a, b) => a.daysUntilExpiry.compareTo(b.daysUntilExpiry));
  return found;
}

/// Rows already past their date.
///
/// Their own group, at the top, because this is a decision rather than a warning: the stock
/// either gets used anyway or written off, and either way it is not going to improve.
List<DatedLot> expiredRows({int horizonDays = defaultHorizonDays}) =>
    datedLots(horizonDays: horizonDays).where((e) => e.isExpired).toList();

/// Rows still good, grouped by where they are, in the order the locations read.
///
/// `forecasting.md` asks for this per location and the use case is why: a cafe's morning
/// check is a walk to the fridge, then the freezer, then the dry store. Grouping matches the
/// walk; sorting by urgency inside a group matches what to pick up first.
Map<String, List<DatedLot>> approachingByLocation({int horizonDays = defaultHorizonDays}) {
  final List<DatedLot> approaching = datedLots(
    horizonDays: horizonDays,
  ).where((e) => !e.isExpired).toList();

  final Map<String, List<DatedLot>> grouped = <String, List<DatedLot>>{};
  for (final FilterOption option in locationOptions) {
    final List<DatedLot> here = approaching.where((e) => e.locationId == option.id).toList();
    if (here.isNotEmpty) grouped[option.fullPath] = here;
  }

  return grouped;
}
