import 'dart:math' as math;

import '../../../app/models/shopping_line.dart';
import '../../../ui/components/shopping_row/shopping_row.dart';
import 'product_fixtures.dart';

/// The shopping list as the preview catalog draws it.
///
/// **These are real [ShoppingLine]s now, not a parallel type carrying pre-written sentences.** The
/// fixture used to hold `reasonDetail: '2 günlük kaldı'`, which a fixture is allowed to do (D98
/// forbids it of the SCHEMA, not of a mockup) and which meant the catalog rendered a string nothing
/// in the app composes. Building the same objects the endpoint produces makes the preview exercise
/// the sentence logic, which is where D46 is actually enforced: reading the reason column top to
/// bottom is how you check that a bucket never became a number.
///
/// Ordered by urgency rather than by aisle. `forecasting.md` puts the product's credibility on the
/// reason column, so the ordering that makes the reasons legible wins over the one matching a
/// supermarket floor plan. Aisle order is worth revisiting once a real list runs past twenty lines.

/// How much to buy to reach the target, rounded up to a whole base unit.
///
/// The server's own rule, restated so the catalog cannot show a quantity the endpoint would not
/// produce: you cannot buy a third of a packet, and for a weight unit the error should land on
/// "enough" rather than on "short again next week".
num _toBuy(ProductListItem product) =>
    math.max(1, ((product.parLevel ?? 0) - product.amount).ceil());

/// A line built from a real product, so the list can never contradict the product screen.
///
/// **The quantities are derived, not typed.** An earlier screen in this app stated one total on a
/// list and a different one on the detail page for the same product, and the fix was to derive both
/// from one source.
ShoppingLine _line(
  String productName, {
  required ShoppingReason reason,
  int? days,
  String? bucket,
  bool? lotIsOpen,
  bool isChecked = false,
}) {
  final ProductListItem product = productFixtures.firstWhere((p) => p.name == productName);
  final num amount = _toBuy(product);

  return ShoppingLine(
    id: 'fixture-${product.name}',
    productId: product.id,
    name: product.name,
    quantity: amount,
    unit: product.unit,
    reason: reason,
    days: days,
    bucket: bucket,
    lotIsOpen: lotIsOpen,
    onHand: product.amount,
    target: product.parLevel,
    movementCount: product.demandCount,
    isChecked: isChecked,
  );
}

/// The list as it stands mid-trip: some things still to get, some already in the trolley.
///
/// **Every certainty tier appears, and the sentence changes shape between them.** That is D46 rather
/// than a fixture flourish: a line may only make the claim its evidence supports, so the milk gets a
/// number, the bulgur gets a bucket, and the screwdriver set gets a bare ratio with no time in it.
List<ShoppingLine> get shoppingLines => <ShoppingLine>[
  // Zero on hand, so there is no cover figure to state: `days` is null and the sentence says the
  // stock is gone. Sending a figure here would be a forecast contradicting the amount beside it.
  _line('Kıyma', reason: ShoppingReason.runningOut),
  // Ten or more demand days: the only tier allowed a number.
  _line('Pınar Süt Tam Yağlı 1 lt', reason: ShoppingReason.runningOut, days: 2),
  // A date rather than a rate, and an opened pot runs on the shorter clock (D27).
  _line('Yoğurt 2 kg', reason: ShoppingReason.expiring, days: 3, lotIsOpen: true),
  // Two to nine demand days: a bucket, never a number at any precision.
  _line('Bulgur', reason: ShoppingReason.roughlyDue, bucket: 'week'),
  _line('Vanilya Tozu 3\'lü', reason: ShoppingReason.roughlyDue, bucket: 'fortnight'),
  // Below the bar: no time claim at all, just the ratio. Both are non-perishables, which is the
  // half of the catalogue a forecast has least to say about.
  _line('Tornavida Seti PH2', reason: ShoppingReason.belowTarget),
  _line('USB-C Kablo 2 m', reason: ShoppingReason.belowTarget, isChecked: true),
  // Not derived from a product: the user typed it, and naming it created nothing (D100).
  const ShoppingLine(
    id: 'fixture-manual',
    name: 'Bulaşık deterjanı',
    quantity: 1,
    unit: 'H87',
    reason: ShoppingReason.manual,
    isChecked: true,
  ),
];

/// Lines still to get.
List<ShoppingLine> get pendingLines =>
    shoppingLines.where((l) => !l.isChecked).toList(growable: false);

/// Lines already in the trolley. Not stock: nothing has arrived until a receipt says so.
List<ShoppingLine> get checkedLines =>
    shoppingLines.where((l) => l.isChecked).toList(growable: false);
