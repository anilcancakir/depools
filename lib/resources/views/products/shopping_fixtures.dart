import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../../ui/components/shopping_row/shopping_row.dart';
import 'product_fixtures.dart';

/// One line of the shopping list, as the screen needs it.
@immutable
class ShoppingFixture {
  /// The product name.
  final String name;

  /// How many to buy.
  final num amount;

  /// The already-formatted quantity.
  final String formatted;

  /// The unit.
  final String unit;

  /// Why this line is here.
  final ShoppingReason reason;

  /// The already-localised evidence behind the reason.
  final String reasonDetail;

  /// Whether the item is in the trolley.
  final bool isChecked;

  /// Creates a [ShoppingFixture].
  const ShoppingFixture({
    required this.name,
    required this.amount,
    required this.formatted,
    required this.reasonDetail,
    this.unit = 'adet',
    this.reason = ShoppingReason.manual,
    this.isChecked = false,
  });
}

/// How much to buy to reach the target, rounded up to a whole base unit.
///
/// Rounding up is the only rule, and it is the safe direction: you cannot buy a third of a
/// packet, and for a weight unit the error lands on "enough" rather than on "short again
/// next week". Stock is held in the base unit, so this is the number the user will actually
/// hand over at the till.
num _toBuy(ProductListItem product) =>
    math.max(1, ((product.parLevel ?? 0) - product.amount).ceil());

/// A line built from a real product, so the list can never contradict the product screen.
///
/// **The quantities are derived, not typed.** An earlier screen in this app stated one
/// total on a list and a different one on the detail page for the same product, and the
/// fix was to derive both from one source. The same trap is wide open here: a shopping list
/// is a claim ABOUT stock, so a hand-written "0 / 2 adet" would drift the first time the
/// product fixture changed.
ShoppingFixture _line(
  String productName, {
  required ShoppingReason reason,
  required String reasonDetail,
  bool isChecked = false,
}) {
  final ProductListItem product = productFixtures.firstWhere((p) => p.name == productName);
  final num amount = _toBuy(product);

  return ShoppingFixture(
    name: product.name,
    amount: amount,
    formatted: '${amount.round()}',
    unit: product.unit,
    reason: reason,
    reasonDetail: reasonDetail,
    isChecked: isChecked,
  );
}

/// The list as it stands mid-trip: some things still to get, some already in the trolley.
///
/// **Every certainty tier appears, and the language changes shape between them.** That is
/// D46 rather than a fixture flourish: a line can only make the claim its data supports, so
/// the milk gets a number, the bulgur gets a bucket, and the screwdriver set gets a bare
/// ratio with no time in it at all. Reading the reason column top to bottom is how you
/// check that the rule held.
///
/// Ordered by urgency, not by aisle. `forecasting.md` puts the product's credibility on the
/// reason column, so the ordering that makes the reasons legible wins over the one that
/// matches a supermarket floor plan. Aisle order is worth revisiting when a real list runs
/// past twenty lines.
List<ShoppingFixture> get shoppingLines => <ShoppingFixture>[
  // Zero on hand, so there is no days-of-cover figure to state. An earlier pass said
  // "1 günlük kaldı" here, which was a forecast contradicting the product's own amount of
  // 0: the arithmetic was derived and the sentence beside it was not.
  _line('Kıyma', reason: ShoppingReason.runningOut, reasonDetail: 'Stok bitti'),
  // 10+ movements: a real days-of-cover figure. The only tier allowed a number.
  _line(
    'Pınar Süt Tam Yağlı 1 lt',
    reason: ShoppingReason.runningOut,
    reasonDetail: '2 günlük kaldı',
  ),
  // A date, not a rate. This one needs replacing whatever the consumption says.
  _line('Yoğurt 2 kg', reason: ShoppingReason.expiring, reasonDetail: 'Açılmış kap · 3 gün ömür'),
  // 2-9 movements: a bucket. Never a number, at any precision.
  _line(
    'Bulgur',
    reason: ShoppingReason.roughlyDue,
    reasonDetail: 'Yaklaşık bir hafta · geçmiş az',
  ),
  _line(
    'Vanilya Tozu 3\'lü',
    reason: ShoppingReason.roughlyDue,
    reasonDetail: 'Yaklaşık on gün · geçmiş az',
  ),
  // 0-1 movements: no time claim at all, just the ratio. Both are non-perishables, which
  // is the half of the catalogue a forecast has least to say about.
  _line(
    'Tornavida Seti PH2',
    reason: ShoppingReason.belowTarget,
    reasonDetail: 'Hedefin altında · 0 / 2 adet',
  ),
  _line(
    'USB-C Kablo 2 m',
    reason: ShoppingReason.belowTarget,
    reasonDetail: 'Hedefin altında · 3 / 10 adet',
    isChecked: true,
  ),
  // Not derived from a product: the user typed it, and it may not be in the catalogue at
  // all. A list that only holds known products is a list people keep on paper instead.
  const ShoppingFixture(
    name: 'Bulaşık deterjanı',
    amount: 1,
    formatted: '1',
    reasonDetail: 'Elle eklendi',
    isChecked: true,
  ),
];

/// Lines still to get.
List<ShoppingFixture> get pendingLines => shoppingLines.where((l) => !l.isChecked).toList();

/// Lines already in the trolley. Not stock: nothing has arrived until a receipt says so.
List<ShoppingFixture> get checkedLines => shoppingLines.where((l) => l.isChecked).toList();
