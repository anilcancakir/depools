import 'count_line.dart';
import 'product_fixtures.dart';

// Demo rows only. The count's domain types are in `count_line.dart` beside this file, because
// `no_hardcoded_copy_test` skips any path containing `fixtures` and those types carry production,
// user-visible copy: that exemption is how `CountLine.verdict` shipped as hardcoded Turkish with a
// green suite. What is left here is what the exemption is FOR, rows standing in for a user's own
// product names, which are not translated.

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
