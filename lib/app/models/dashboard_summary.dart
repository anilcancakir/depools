import 'package:flutter/foundation.dart' show immutable;

import '../../resources/views/products/expiring_fixtures.dart';
import '../../resources/views/products/product_fixtures.dart';
import 'movement_entry.dart';

/// Everything the landing screen draws, from one response.
///
/// **One object because it is one request**, and that is the screen's own rule rather than a
/// convenience: `DashboardView` says no figure on it may disagree with the page it links to, and
/// four separately-fetched pieces would each arrive at their own moment.
///
/// The counters are carried SEPARATELY from the lists they head, because they count different
/// things: the list is the first three rows and the counter is the whole set. Deriving the counter
/// from the list would make every card say "3" however many products are actually short.
@immutable
class DashboardSummary {
  /// Whether the tenant has any stock at all.
  ///
  /// Decides which SCREEN they get rather than how full it is: a fresh tenant sees the setup steps,
  /// because the counters, the four cards and the history all describe stock and would render as six
  /// ways of saying the same nothing.
  final bool hasStock;

  /// How many products the tenant has, for the subtitle's scope.
  final int products;

  /// How many locations, likewise.
  final int locations;

  /// Lots already past their date.
  final int expiredCount;

  /// Lots inside the horizon and still good.
  final int approachingCount;

  /// Products holding nothing.
  final int outOfStockCount;

  /// Products below a target somebody actually set.
  final int belowTargetCount;

  /// The first few expired lots, for the dates card.
  final List<DatedLot> expired;

  /// The first few approaching lots, likewise.
  final List<DatedLot> approaching;

  /// The first few products holding nothing.
  final List<ProductListItem> outOfStock;

  /// The first few products below target.
  final List<ProductListItem> belowTarget;

  /// The last few ledger entries, across every product.
  final List<MovementEntry> activity;

  /// Creates a [DashboardSummary].
  const DashboardSummary({
    required this.hasStock,
    required this.products,
    required this.locations,
    required this.expiredCount,
    required this.approachingCount,
    required this.outOfStockCount,
    required this.belowTargetCount,
    required this.expired,
    required this.approaching,
    required this.outOfStock,
    required this.belowTarget,
    required this.activity,
  });

  /// Reads one from `/dashboard`, or null when the payload cannot make a screen.
  ///
  /// Null rather than a partial screen: a dashboard missing one card is a dashboard that has quietly
  /// stopped answering the question it exists for, and a user cannot tell which half they are
  /// looking at.
  static DashboardSummary? fromApi(
    Map<String, dynamic> json, {
    required Map<String, String> locationLabels,
  }) {
    final Object? counters = json['counters'];

    if (counters is! Map<String, dynamic>) return null;

    return DashboardSummary(
      hasStock: json['has_stock'] == true,
      products: _int(json['products']),
      locations: _int(json['locations']),
      expiredCount: _int(counters['expired']),
      approachingCount: _int(counters['approaching']),
      outOfStockCount: _int(counters['out_of_stock']),
      belowTargetCount: _int(counters['below_target']),
      expired: _lots(json['expired']),
      approaching: _lots(json['approaching']),
      outOfStock: _items(json['out_of_stock'], locationLabels),
      belowTarget: _items(json['below_target'], locationLabels),
      activity: _movements(json['activity']),
    );
  }

  static int _int(Object? value) => value is num ? value.toInt() : 0;

  static List<DatedLot> _lots(Object? data) {
    if (data is! List) return const <DatedLot>[];

    return data
        .whereType<Map<String, dynamic>>()
        .map((Map<String, dynamic> row) => DatedLot.fromApi(row))
        .whereType<DatedLot>()
        .toList();
  }

  static List<ProductListItem> _items(Object? data, Map<String, String> labels) {
    if (data is! List) return const <ProductListItem>[];

    return data
        .whereType<Map<String, dynamic>>()
        .map((Map<String, dynamic> row) => ProductListItem.fromApi(row, locationLabels: labels))
        .toList();
  }

  static List<MovementEntry> _movements(Object? data) {
    if (data is! List) return const <MovementEntry>[];

    return data
        .whereType<Map<String, dynamic>>()
        .map(MovementEntry.fromMap)
        .whereType<MovementEntry>()
        .toList();
  }
}
