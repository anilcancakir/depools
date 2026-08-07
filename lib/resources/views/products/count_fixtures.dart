import 'package:flutter/foundation.dart';

import 'product_fixtures.dart';

/// One product being counted in one location.
@immutable
class CountLine {
  /// The product.
  final ProductListItem product;

  /// What the system believes is here, in the base unit.
  final num expected;

  /// The whole units counted, or null when nobody has counted yet.
  final num? countedWhole;

  /// The opened-unit amount counted, for a product with a content level.
  final num? countedRemainder;

  /// Creates a [CountLine].
  const CountLine({
    required this.product,
    required this.expected,
    this.countedWhole,
    this.countedRemainder,
  });

  /// Whether anybody has entered anything.
  ///
  /// **Not counted is not zero.** An untouched row is left completely alone at commit; a row
  /// counted as zero writes the whole balance off. Collapsing the two would zero out every
  /// product the user did not reach.
  bool get isCounted => countedWhole != null;

  /// The counted total in the base unit, combining both fields.
  num? get countedTotal {
    if (countedWhole == null) return null;
    final num content = product.contentAmount ?? 1;
    final num inner = (countedRemainder ?? 0) / content;
    return countedWhole! + inner;
  }

  /// Counted minus expected. Null while uncounted, because there is no difference to state.
  num? get variance => countedTotal == null ? null : countedTotal! - expected;

  /// Whether the count agreed with the system.
  bool get isMatched => variance != null && variance!.abs() < 0.0001;

  /// A base-unit figure written the way D26 requires: a whole count and an open remainder,
  /// never one decimal. `1.5` becomes `1 adet + 500 ml`, because nobody can verify "1,5
  /// adet" against a shelf.
  ///
  /// One formatter, used by the row's verdict AND by the summary, so the two can never
  /// disagree about the same number.
  String figure(num value) {
    final int whole = value.floor();
    final num content = product.contentAmount ?? 1;
    final int inner = ((value - whole) * content).round();
    final String head = '$whole ${product.unit}';
    if (inner == 0 || product.contentUnit == null) return head;
    // A zero whole is dropped when there is an inner amount. Half a carton is "500 ml", not
    // "0 adet + 500 ml": the leading zero is noise, it reads as a contradiction beside a
    // non-zero remainder, and it was long enough to truncate the verdict line it sat in.
    if (whole == 0) return '$inner ${product.contentUnit}';
    return '$head + $inner ${product.contentUnit}';
  }

  /// The already-localised verdict line, blind until something is counted (D58).
  String get verdict {
    if (!isCounted) return 'Sayılmadı';
    if (isMatched) return 'Eşleşti · sistemde ${figure(expected)}';

    final num diff = variance!;
    final String sign = diff > 0 ? 'fazla' : 'eksik';
    return 'Sistemde ${figure(expected)} · ${figure(diff.abs())} $sign';
  }
}

/// What the system expects to find in one location.
///
/// `amountAt` sums LOTS, which is right for a product that has them and returns zero for one
/// that does not. A lot-less product's whole balance sits in its single location, so that is
/// the fallback. **It is only valid because a lot-less product has exactly one location**, and
/// `test/stock_take_test.dart` asserts that rather than trusting it: if a product ever gets
/// two locations without lots to split them, this would silently report its entire balance in
/// both places.
num expectedAt(ProductListItem product, String locationId) =>
    product.lots.isEmpty ? product.amount : product.amountAt(locationId);

/// A part-finished count of the fridge.
///
/// Three states on purpose, because they are the whole design. The milk has been counted and
/// disagrees, the cheese has been counted and agrees, and the yoghurt has not been counted at
/// all. The milk is also the hard case: it holds a sealed carton plus an opened half-litre, so
/// it is counted in two fields, and the counter found the sealed one and no open one.
List<CountLine> get fridgeCount => <CountLine>[
  CountLine(
    product: _product('Pınar Süt Tam Yağlı 1 lt'),
    expected: expectedAt(_product('Pınar Süt Tam Yağlı 1 lt'), 'loc-fridge'),
    countedWhole: 1,
    countedRemainder: 0,
  ),
  CountLine(
    product: _product('Kaşar Peyniri 500 g'),
    expected: expectedAt(_product('Kaşar Peyniri 500 g'), 'loc-fridge'),
    countedWhole: 1,
  ),
  CountLine(
    product: _product('Yoğurt 2 kg'),
    expected: expectedAt(_product('Yoğurt 2 kg'), 'loc-fridge'),
  ),
];

/// Lines somebody has counted.
List<CountLine> get countedLines => fridgeCount.where((l) => l.isCounted).toList();

/// Lines nobody has reached. Left untouched at commit.
List<CountLine> get skippedLines => fridgeCount.where((l) => !l.isCounted).toList();

/// Counted lines that disagree with the system.
///
/// **Only these write movements.** A count that agrees changes nothing, so writing a
/// zero-delta row would be recording a non-event, and it would do measurable harm: the
/// movement count is what decides a product's forecast tier, so zero-delta rows would push
/// products into "we can forecast this" on the strength of counts rather than consumption.
List<CountLine> get varianceLines =>
    countedLines.where((l) => !l.isMatched).toList(growable: false);

ProductListItem _product(String name) => productFixtures.firstWhere((p) => p.name == name);
