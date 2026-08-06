import 'package:flutter/foundation.dart';

import '../../../app/models/product_filter.dart';
import 'product_filter_sheet.dart';

/// How a product's units are identified.
///
/// D28 ships both in v1, chosen per product. They are mutually exclusive by nature
/// rather than by policy: a lot is a quantity of interchangeable things, a serial is
/// one specific thing, and the partial-consumption model (D26) only makes sense for
/// the first. Half a drill does not exist.
enum TrackingMode {
  /// Fungible units. Quantities add up, lots carry expiry, halves are possible.
  lot,

  /// Individually identified units. One row per physical item with its own serial and
  /// its own warranty, quantities are whole counts, no partial consumption.
  serial,
}

/// One individually identified unit: a serial number and what is known about it.
///
/// The serial-tracking counterpart to [LotFixture]. The differences are the point:
/// there is no remaining amount because a unit is present or it is not, and the date
/// that matters is a warranty end rather than an expiry.
///
/// **The warranty reuses the expiry machinery deliberately.** Same derived warning
/// window, same badge, same place in the attention list. A warranty running out and a
/// carton going off are the same shape of problem (a date that makes something worth
/// less once it passes), and giving them two mechanisms would mean two things to keep
/// in sync for no gain.
@immutable
class SerialFixture {
  /// The serial, IMEI or asset tag. Rendered in mono, because it gets read aloud and
  /// typed back in.
  final String serial;

  /// Days until the warranty ends. Negative means it already has, null means none.
  final int? warrantyDaysRemaining;

  /// The already-formatted warranty label for a badge.
  final String? warrantyLabel;

  /// The already-formatted acquisition line.
  final String? receivedLabel;

  /// Which location holds this unit.
  final String locationId;

  /// Whether this unit has left. Kept for the history, excluded from counts.
  final bool isGone;

  /// Creates a [SerialFixture].
  const SerialFixture({
    required this.serial,
    required this.locationId,
    this.warrantyDaysRemaining,
    this.warrantyLabel,
    this.receivedLabel,
    this.isGone = false,
  });
}

/// One lot of a product: a batch with its own date and its own remaining amount.
///
/// The lots are the SOURCE for a product's totals, not a second opinion about them.
/// Both product screens hand-wrote their own numbers before this existed and they
/// drifted three ways in one sitting: the detail screen claimed 5 adet while the list
/// claimed 2.5, its target said 6 against the list's 4, and its lots summed to 4.5
/// while holding an expired carton the list knew nothing about.
@immutable
class LotFixture {
  /// Remaining amount, in base units. A half-used 1 lt carton is 0.5.
  final num remaining;

  /// The already-formatted remaining figure, in [unit].
  final String formatted;

  /// The unit this lot's remainder is expressed in.
  ///
  /// An open lot reports in the product's CONTENT unit (500 ml), a sealed one in its
  /// base unit (1 adet). That is not an inconsistency: it is what the user sees when
  /// they pick the thing up.
  final String unit;

  /// Days until this lot's binding date, whichever that is.
  ///
  /// For an open lot it is the after-opening limit, not the printed date (D27).
  final int? daysUntilExpiry;

  /// The already-formatted date label for a badge.
  final String? expiryLabel;

  /// Whether this lot has been opened and is on its after-opening clock.
  final bool isOpen;

  /// The already-formatted opening line, when open.
  final String? openedLabel;

  /// The already-formatted arrival line, when sealed.
  final String? receivedLabel;

  /// The supplier's batch code, when known.
  final String? lotCode;

  /// Whether this lot reached zero. Excluded from every total, kept for the history.
  final bool isDepleted;

  /// Which location holds this lot.
  final String locationId;

  /// Creates a [LotFixture].
  const LotFixture({
    required this.remaining,
    required this.formatted,
    required this.unit,
    required this.locationId,
    this.daysUntilExpiry,
    this.expiryLabel,
    this.isOpen = false,
    this.openedLabel,
    this.receivedLabel,
    this.lotCode,
    this.isDepleted = false,
  });
}

/// One product as the stock list needs it.
///
/// The list was built from hardcoded `ProductRow` widgets, which was fine while it
/// only had to render. It cannot stay that way now that the screen filters: a filter
/// over widgets is not a filter, and the count in the sheet's apply button has to
/// come from the same source the list renders, or the two will disagree.
///
/// This is deliberately not a `MagicModel`. It is the shape the eventual
/// `ProductController` will hand the view, so building it now means the controller
/// swap replaces where the rows come from and touches nothing else. The fixtures
/// stay afterwards as the preview catalog's data source.
@immutable
class ProductListItem {
  /// Product name.
  final String name;

  /// Brand, if known.
  final String? brand;

  /// The ids of every location holding stock of this product.
  final Set<String> locationIds;

  /// The already-joined location text for the row's meta line.
  final String locationSummary;

  /// Category id.
  final String? categoryId;

  /// Tags.
  final Set<String> tags;

  /// Total on hand across every location, in base units.
  ///
  /// Fractional when something is open: two whole cartons plus a half-used one is
  /// 2.5. This is the number every threshold compares against; it is never what the
  /// screen prints, because "2,5 adet" is not how anyone describes their fridge.
  final num amount;

  /// The already-formatted count of WHOLE base units, for the active locale.
  final String formatted;

  /// Base unit: the unit stock is held in, for example `adet`, `kg`, `paket`.
  final String unit;

  /// What one base unit contains, and in which unit.
  ///
  /// One declaration covers both shapes D25 allows: a 1 lt carton is
  /// `contentAmount: 1000, contentUnit: 'ml'`, and a pack of three sachets is
  /// `contentAmount: 3, contentUnit: 'poşet'`. Turkish labelling law states the same
  /// pair (per-pack net content plus total pack count), so the fields are the ones
  /// the box itself already carries.
  ///
  /// Null means the product is not divisible, or its content is simply unknown. Both
  /// collapse to the same behaviour: no partial tracking, no remainder to render.
  final num? contentAmount;

  /// The content unit. Null together with [contentAmount].
  final String? contentUnit;

  /// How much is left in the one open unit, in content units.
  ///
  /// Null when nothing is open. Exactly one unit can be open at a time here, which
  /// is a simplification worth naming: a cafe with three opened cartons is real, and
  /// the ledger will hold one opened lot each. The list row only has room for one
  /// figure, so it shows the earliest-expiring open unit and the detail screen shows
  /// them all.
  final num? openRemainder;

  /// Days until the OPEN unit must be used, which is not the printed date.
  ///
  /// An opened carton with ten days left on the box spoils in three (D27). Null when
  /// nothing is open or the product declares no after-opening limit.
  final int? openDaysRemaining;

  /// The user-set target level, used for the below-par test. Null means unset, and
  /// an unset target can never be "below par": that state has to mean something the
  /// user chose, or every product with a little stock would report as running low.
  final num? parLevel;

  /// Days until the date that actually matters, whichever comes first.
  ///
  /// For a sealed product that is the earliest lot's printed date. Once something is
  /// opened it is the OPEN unit's after-opening limit, which is usually much sooner:
  /// a carton with a week left on the box has three days left once opened (D27).
  ///
  /// The row needs one number because it shows one badge. The detail screen has the
  /// room to show both, and it should, because "opened yesterday" and "printed date
  /// next Tuesday" are two different facts about the same carton.
  final int? daysUntilExpiry;

  /// The product's shelf life in days, from `products.default_shelf_life_days`.
  ///
  /// Drives [expiryThresholdDays]. Null means unknown, which falls back to the
  /// neutral default rather than to no warning: a product with an expiry date and no
  /// declared shelf life still has to be able to warn.
  final int? shelfLifeDays;

  /// The already-formatted expiry label for the row.
  final String? expiryLabel;

  /// The product's own description, as printed on the pack or written by the user.
  final String? description;

  /// The tenant's SKU.
  final String? sku;

  /// The category's already-localised label, for the identity card's tag.
  final String? categoryLabel;

  /// The barcodes on this product, as (code, meta) pairs.
  ///
  /// Held here rather than on the screen because a second product proved the point:
  /// the detail screen showed a carton of milk's EAN-13 on a power drill, which is the
  /// same class of defect as the totals drifting and has the same fix.
  final List<(String, String)> barcodes;

  /// How this product's units are identified.
  ///
  /// Drives which section the detail screen shows and whether partial amounts are
  /// offered at all. Defaults to [TrackingMode.lot], because that is what most stock
  /// is and because a serial-tracked product has to opt in by declaring serials.
  final TrackingMode tracking;

  /// The individually identified units, when [tracking] is [TrackingMode.serial].
  final List<SerialFixture> serials;

  /// The lots behind this product's stock, when the fixture declares them.
  ///
  /// When non-empty these are authoritative: [amount], [openRemainder] and
  /// [daysUntilExpiry] are all derivable from them, and the detail screen renders
  /// them directly, so the two screens cannot disagree about one product. Products
  /// that only ever appear in the list can leave it empty and pass the totals
  /// directly.
  final List<LotFixture> lots;

  /// Creates a [ProductListItem].
  const ProductListItem({
    required this.name,
    required this.amount,
    required this.formatted,
    required this.unit,
    this.brand,
    this.locationIds = const {},
    this.locationSummary = '',
    this.categoryId,
    this.tags = const {},
    this.parLevel,
    this.daysUntilExpiry,
    this.expiryLabel,
    this.shelfLifeDays,
    this.contentAmount,
    this.contentUnit,
    this.openRemainder,
    this.openDaysRemaining,
    this.lots = const [],
    this.tracking = TrackingMode.lot,
    this.serials = const [],
    this.description,
    this.sku,
    this.categoryLabel,
    this.barcodes = const [],
  });

  /// The units still on hand.
  List<SerialFixture> get liveSerials => serials.where((u) => !u.isGone).toList();

  /// The units at one location.
  List<SerialFixture> serialsAt(String locationId) =>
      serials.where((u) => u.locationId == locationId && !u.isGone).toList();

  /// The lots that still hold something, earliest binding date first.
  ///
  /// Depleted lots are excluded from every total and kept for the history, which is
  /// why they are filtered here rather than removed from the fixture.
  List<LotFixture> get liveLots => lots.where((l) => !l.isDepleted).toList();

  /// The lots at one location.
  List<LotFixture> lotsAt(String locationId) =>
      lots.where((l) => l.locationId == locationId && !l.isDepleted).toList();

  /// Stock at one location, derived from whichever unit model this product uses.
  ///
  /// A serial-tracked location holds a whole COUNT, which is the difference that
  /// matters: there is no fraction to sum because a unit is present or it is not.
  ///
  /// Summing lots unconditionally left the serial-tracked screen reporting "0 konum"
  /// beside two drills sitting on a shelf. That is the second time a lot-shaped
  /// assumption has quietly broken the other mode, which is the standing cost of D28
  /// and the reason both paths need a fixture and a preview.
  num amountAt(String locationId) => tracking == TrackingMode.serial
      ? serialsAt(locationId).length
      : lotsAt(locationId).fold<num>(0, (sum, l) => sum + l.remaining);

  /// Whether one unit is open and partly used.
  bool get hasOpenUnit => openRemainder != null && openRemainder! > 0;

  /// The count of whole, unopened base units.
  ///
  /// Derived by taking the floor of the total, so it cannot disagree with [amount].
  /// Holding it as its own field would let a rounding change put "2 adet + 500 ml"
  /// next to a total of 2.4.
  num get wholeCount => amount.floor();

  /// The figure the row prints first, and its unit.
  ///
  /// **When nothing is whole, the open remainder becomes the primary figure.** A pack
  /// with two sachets left reads "2 poşet", not "0 paket + 2 poşet": the zero is
  /// noise, and worse, `Quantity` would mute the whole row as depleted when the user
  /// still has something to cook with.
  ///
  /// This is the decision `Quantity` deliberately does not make, because it needs the
  /// content declaration and the locale's pluralisation.
  (String, String?) get primaryFigure {
    if (wholeCount == 0 && hasOpenUnit) {
      return (_format(openRemainder!), contentUnit);
    }
    return (formatted, unit);
  }

  /// The trailing `+ N unit` part, or null when there is nothing to add.
  ///
  /// Null when nothing is open, and null when the remainder is already the primary
  /// figure, which is what keeps the two from being printed twice.
  (String, String?)? get remainderFigure {
    if (!hasOpenUnit || wholeCount == 0) return null;
    return (_format(openRemainder!), contentUnit);
  }

  /// The already-localised note explaining an open unit, for the row's meta line.
  ///
  /// Only worth saying when the remainder is the primary figure. "2 adet + 500 ml"
  /// already tells the reader something is open; "2 poşet" does not, and without the
  /// note the user cannot tell two loose sachets from two sealed packs.
  String? get openNote {
    if (!hasOpenUnit || wholeCount > 0) return null;
    return '1 $unit açık';
  }

  /// Turkish decimal formatting for a content figure.
  ///
  /// Whole values lose the decimals: "500 ml", not "500,00 ml". A remainder is read
  /// at a glance and the trailing zeros are noise at that size.
  static String _format(num value) {
    if (value == value.roundToDouble()) return value.round().toString();
    return value.toStringAsFixed(2).replaceAll('.', ',');
  }

  /// The neutral window used when a product declares no shelf life.
  static const int fallbackThresholdDays = 7;

  /// The longest warning window, in days.
  ///
  /// Without a ceiling the proportion runs away on long-life goods: a tin with a two
  /// year shelf life would start warning 146 days out, which is noise rather than
  /// signal. Two months is the point where a tin becomes worth acting on.
  static const int maxThresholdDays = 60;

  /// How many days before expiry this product starts needing attention.
  ///
  /// **Derived per product rather than fixed**, which is the decision recorded in
  /// `open-decisions.md`. One global number cannot be right for both milk and flour:
  /// seven days always warns about a five-day carton and never warns about a tin.
  ///
  /// The window is the last fifth of the shelf life, floored at one day and capped
  /// at [maxThresholdDays]. Milk (5 days) warns 1 day out; a tin (730 days) warns 60
  /// days out. Those two ends are what the proportion was chosen to satisfy.
  int get expiryThresholdDays {
    final int life = shelfLifeDays ?? fallbackThresholdDays * 5;
    return (life * 0.2).round().clamp(1, maxThresholdDays);
  }

  /// The meta line under the name: brand and where it is.
  String? get meta {
    final List<String> parts = <String>[?brand, if (locationSummary.isNotEmpty) locationSummary];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  /// Whether this product needs attention.
  ///
  /// Four conditions, and the order of that list is the point: **out of stock and
  /// below par come first, because they are the only ones a product without an expiry
  /// date can trigger.** An earlier version tested expiry and zero stock only, which
  /// meant a workshop tracking spare parts or a shop tracking chargers got an empty
  /// attention section no matter how low it ran. This is not a food app; expiry is one
  /// signal among several rather than the organising one.
  ///
  /// It is deliberately the same predicate the built-in saved filters use, so the
  /// section and the chips cannot disagree. They did once: the section hardcoded two
  /// days while the filter used seven, so a product could pass "Yakında bitecek" and
  /// be missing from the section that exists to surface exactly that.
  bool get needsAttention =>
      amount == 0 || isOpenAndPerishable || isBelowPar || isExpired || isExpiringSoon;

  /// Whether an open unit is on its after-opening clock.
  ///
  /// **An open unit with a declared after-opening limit is ALWAYS in the attention
  /// list, for as long as it is open.** Not on a proportion of anything: the
  /// proportional window that works for a printed date breaks down here, because 20%
  /// of a three-day after-opening life is under a day, so an opened carton with two
  /// days left would stay silent until its last morning.
  ///
  /// It is also the right answer on its own terms. An opened container is the single
  /// item most likely to be wasted, and telling the user about it is the promise the
  /// product is built on.
  ///
  /// Gated on the limit being declared, so an opened bag of flour does not sit in the
  /// attention list forever. Opening something shelf-stable is not an event.
  bool get isOpenAndPerishable => hasOpenUnit && openDaysRemaining != null;

  /// Whether stock has fallen to or below the user's own target level.
  ///
  /// Requires a target the user actually set. Without the null guard, every product
  /// holding a small amount would report as running low, and "below par" has to mean
  /// something someone chose.
  bool get isBelowPar => parLevel != null && amount > 0 && amount <= parLevel!;

  /// Whether the earliest lot is already past its date.
  bool get isExpired => daysUntilExpiry != null && daysUntilExpiry! < 0;

  /// Whether the earliest lot falls inside this product's own warning window.
  ///
  /// Already expired is NOT expiring soon. They are different situations and the user
  /// picks one of them; folding them together would make "Yakında bitecek" include
  /// things that went off last month.
  bool get isExpiringSoon =>
      daysUntilExpiry != null && daysUntilExpiry! >= 0 && daysUntilExpiry! <= expiryThresholdDays;

  /// Whether this product satisfies [filter].
  ///
  /// Every axis is an AND, and an empty axis is not a constraint. Free text matches
  /// name or brand, case-insensitively: a user typing "pinar" should find "Pınar",
  /// so the comparison is lowercased on both sides.
  bool matches(ProductFilter filter) {
    if (filter.query.isNotEmpty) {
      final String needle = filter.query.toLowerCase();
      final bool hit =
          name.toLowerCase().contains(needle) || (brand?.toLowerCase().contains(needle) ?? false);
      if (!hit) return false;
    }

    if (filter.locationIds.isNotEmpty && locationIds.intersection(filter.locationIds).isEmpty) {
      return false;
    }

    if (filter.categoryIds.isNotEmpty && !filter.categoryIds.contains(categoryId)) {
      return false;
    }

    if (filter.tags.isNotEmpty && tags.intersection(filter.tags).isEmpty) return false;

    if (filter.brands.isNotEmpty && !filter.brands.contains(brand)) return false;

    switch (filter.stockState) {
      case StockStateFilter.any:
        break;
      case StockStateFilter.outOfStock:
        if (amount != 0) return false;
      case StockStateFilter.belowPar:
        if (!isBelowPar) return false;
      case StockStateFilter.inStock:
        if (amount == 0) return false;
    }

    switch (filter.expiry) {
      case ExpiryFilter.any:
        break;
      case ExpiryFilter.expired:
        if (!isExpired) return false;
      case ExpiryFilter.expiringSoon:
        if (!isExpiringSoon) return false;
    }

    return true;
  }
}

/// The stock list fixtures.
///
/// Chosen so every filter axis has at least one product that passes and one that
/// fails it, which is what makes the filter testable by hand in the catalog: an
/// expired item, one inside its own warning window, one out of stock, one below its
/// target, and several plain ones across several categories and four locations.
///
/// **Two of them deliberately track no expiry at all.** This is not a food app, and a
/// fixture set that was entirely perishable let a real defect through: the attention
/// section tested expiry and zero stock only, so a tenant tracking spare parts or
/// chargers saw an empty section however low they ran. A cable below its target level
/// and a tool at zero are what keep that honest, and they are also what the screen
/// looks like for a workshop rather than a kitchen.
const List<ProductListItem> productFixtures = <ProductListItem>[
  // The partial-consumption case, and the reason D26 and D27 exist. Two sealed
  // cartons plus one opened with half a litre left: the total is 2.5 base units, the
  // row prints "2 adet + 500 ml", and the badge reports the OPENED unit's three-day
  // limit rather than the printed date, which still has a week to run.
  ProductListItem(
    name: 'Pınar Süt Tam Yağlı 1 lt',
    brand: 'Pınar',
    // Sealed cartons in the pantry, the open one in the fridge. A product genuinely
    // split across locations is what keeps the location filter honest.
    locationIds: {'loc-fridge', 'loc-pantry'},
    locationSummary: 'Buzdolabı, Kiler',
    categoryId: 'cat-dairy',
    tags: {'kahvaltı', 'soğuk zincir'},
    categoryLabel: 'Süt ürünleri',
    description:
        'Tam yağlı, pastörize inek sütü. 1 litre karton ambalaj, açıldıktan sonra '
        'buzdolabında 3 gün içinde tüketilmeli.',
    sku: 'SUT-PNR-1L',
    barcodes: [('8690123456789', 'EAN-13 · üretici'), ('DP-0042', 'Code128 · bizim bastığımız')],
    amount: 2.5,
    formatted: '2',
    unit: 'adet',
    contentAmount: 1000,
    contentUnit: 'ml',
    openRemainder: 500,
    openDaysRemaining: 2,
    expiryLabel: 'Açık · 2 gün',
    daysUntilExpiry: 2,
    parLevel: 4,
    shelfLifeDays: 5,
    // These lots ARE the total: 0.5 + 1 + 1 = 2.5 adet, which is what `amount` says
    // above and what the detail screen renders. The depleted one is excluded from the
    // sum and kept as the evidence behind the consumption history.
    lots: [
      LotFixture(
        remaining: 0.5,
        formatted: '500',
        unit: 'ml',
        locationId: 'loc-fridge',
        isOpen: true,
        daysUntilExpiry: 2,
        expiryLabel: '2 gün',
        openedLabel: '5 Ağu açıldı · kutuda 12 Ağu yazıyor',
      ),
      LotFixture(
        remaining: 1,
        formatted: '1',
        unit: 'adet',
        locationId: 'loc-fridge',
        daysUntilExpiry: 6,
        expiryLabel: '6 gün',
        receivedLabel: '3 Ağu alındı',
        lotCode: 'L2408-33',
      ),
      LotFixture(
        remaining: 1,
        formatted: '1',
        unit: 'adet',
        locationId: 'loc-pantry',
        daysUntilExpiry: 12,
        expiryLabel: '12 gün',
        receivedLabel: '5 Ağu alındı',
      ),
      LotFixture(
        remaining: 0,
        formatted: '0',
        unit: 'adet',
        locationId: 'loc-fridge',
        daysUntilExpiry: -24,
        expiryLabel: '12 Tem',
        receivedLabel: '8 Tem alındı',
        isDepleted: true,
      ),
    ],
  ),
  // The pack case from Turkish labelling law: one pack declares three sachets. Two
  // sachets are left out of an opened pack, so nothing is whole and the remainder
  // becomes the primary figure: "2 poşet", with "1 paket açık" underneath. Printing
  // "0,67 paket" would be arithmetically true and useless.
  ProductListItem(
    name: 'Vanilya Tozu 3\'lü',
    brand: 'Dr. Oetker',
    locationIds: {'loc-pantry'},
    locationSummary: 'Kiler › Raf 1',
    categoryId: 'cat-grain',
    amount: 0.67,
    formatted: '0',
    unit: 'paket',
    contentAmount: 3,
    contentUnit: 'poşet',
    openRemainder: 2,
    parLevel: 2,
  ),
  // Expired, and deliberately still here: the attention list has to hold a product
  // that is past its date as well as one that is merely open.
  ProductListItem(
    name: 'Kaşar Peyniri 500 g',
    brand: 'Pınar',
    locationIds: {'loc-fridge'},
    locationSummary: 'Buzdolabı',
    categoryId: 'cat-dairy',
    tags: {'kahvaltı'},
    amount: 1,
    formatted: '1',
    unit: 'adet',
    contentAmount: 500,
    contentUnit: 'g',
    daysUntilExpiry: -1,
    expiryLabel: 'Süresi geçti',
    shelfLifeDays: 30,
  ),
  ProductListItem(
    name: 'Bulgur',
    brand: 'Duru',
    locationIds: {'loc-drawer'},
    locationSummary: 'Çekmece 2',
    categoryId: 'cat-grain',
    tags: {'bakliyat'},
    amount: 0.8,
    formatted: '0,80',
    unit: 'kg',
    parLevel: 2,
    daysUntilExpiry: 2,
    expiryLabel: '2 gün',
    shelfLifeDays: 365,
  ),
  ProductListItem(
    name: 'Kıyma',
    brand: 'Dana',
    locationIds: {'loc-freezer'},
    locationSummary: 'Derin dondurucu',
    categoryId: 'cat-meat',
    amount: 0,
    formatted: '0',
    unit: 'kg',
    parLevel: 1,
  ),
  ProductListItem(
    name: 'Ayçiçek Yağı 5 lt',
    brand: 'Yudum',
    locationIds: {'loc-pantry'},
    locationSummary: 'Kiler › Raf 2',
    categoryId: 'cat-oil',
    amount: 2,
    formatted: '2',
    unit: 'adet',
  ),
  ProductListItem(
    name: 'Yoğurt 2 kg',
    brand: 'Sütaş',
    locationIds: {'loc-fridge'},
    locationSummary: 'Buzdolabı',
    categoryId: 'cat-dairy',
    tags: {'kahvaltı', 'soğuk zincir'},
    amount: 1,
    formatted: '1',
    unit: 'adet',
    daysUntilExpiry: 9,
    expiryLabel: '9 gün',
    // 21 days of shelf life gives a 4 day window, so 9 days out this is NOT yet in
    // the attention list. The same 9 days on the milk above would be.
    shelfLifeDays: 21,
  ),
  ProductListItem(
    name: 'Un',
    brand: 'Söke',
    locationIds: {'loc-pantry'},
    locationSummary: 'Kiler › Raf 1',
    categoryId: 'cat-grain',
    tags: {'bakliyat'},
    amount: 12.5,
    formatted: '12,50',
    unit: 'kg',
    parLevel: 5,
  ),
  // No expiry, below its target. This is the row a workshop or a shop opens the
  // screen for, and it has to reach the attention section on stock level alone.
  ProductListItem(
    name: 'USB-C Kablo 2 m',
    brand: 'Anker',
    locationIds: {'loc-shelf'},
    locationSummary: 'Depo › Raf A',
    categoryId: 'cat-electronics',
    tags: {'sarf'},
    amount: 3,
    formatted: '3',
    unit: 'adet',
    parLevel: 10,
  ),
  // The serial-tracked case (D28). Two drills on hand, each its own object with its
  // own warranty, and one sold. No expiry, no content, no partial anything: the whole
  // reason this mode exists is that "1.5 drills" is not a state the world has.
  //
  // One warranty is inside its warning window, which is what puts this product in the
  // attention list. A shop that misses a warranty expiry eats the repair.
  ProductListItem(
    name: 'Makita Matkap DHP484',
    brand: 'Makita',
    locationIds: {'loc-shelf'},
    locationSummary: 'Depo › Raf A',
    categoryId: 'cat-tools',
    categoryLabel: 'El aleti',
    description:
        '18V akülü darbeli matkap, 2 aküyle. Garanti süresi 2 yıl ve her ünite kendi '
        'seri numarasıyla takip ediliyor.',
    sku: 'MK-DHP484',
    barcodes: [('088381872690', 'EAN-13 · üretici')],
    amount: 2,
    formatted: '2',
    unit: 'adet',
    parLevel: 2,
    daysUntilExpiry: 2,
    expiryLabel: 'Garanti · 2 gün',
    shelfLifeDays: 730,
    tracking: TrackingMode.serial,
    serials: [
      SerialFixture(
        serial: 'MK-DHP484-002391',
        locationId: 'loc-shelf',
        warrantyDaysRemaining: 2,
        warrantyLabel: 'Garanti · 2 gün',
        receivedLabel: '12 Şub alındı · Tekno A.Ş.',
      ),
      SerialFixture(
        serial: 'MK-DHP484-002392',
        locationId: 'loc-shelf',
        warrantyDaysRemaining: 190,
        warrantyLabel: '190 gün',
        receivedLabel: '12 Şub alındı · Tekno A.Ş.',
      ),
      SerialFixture(
        serial: 'MK-DHP484-001044',
        locationId: 'loc-shelf',
        warrantyDaysRemaining: -80,
        warrantyLabel: 'Garanti bitti',
        receivedLabel: 'satıldı · 8 Tem',
        isGone: true,
      ),
    ],
  ),
  // No expiry, at zero.
  ProductListItem(
    name: 'Tornavida Seti PH2',
    brand: 'Ceta Form',
    locationIds: {'loc-shelf'},
    locationSummary: 'Depo › Raf A',
    categoryId: 'cat-tools',
    amount: 0,
    formatted: '0',
    unit: 'adet',
    parLevel: 2,
  ),
];

/// The location options the filter sheet offers, ordered as the tree reads.
const List<FilterOption> locationOptions = <FilterOption>[
  FilterOption(id: 'loc-fridge', label: 'Buzdolabı', path: 'Mutfak › Buzdolabı'),
  FilterOption(id: 'loc-freezer', label: 'Derin dondurucu', path: 'Mutfak › Derin dondurucu'),
  FilterOption(id: 'loc-pantry', label: 'Kiler', path: 'Kiler › Raf 2'),
  FilterOption(id: 'loc-drawer', label: 'Çekmece 2', path: 'Kiler › Çekmece 2'),
  FilterOption(id: 'loc-shelf', label: 'Raf A', path: 'Depo › Raf A'),
];

/// The category options the filter sheet offers.
const List<FilterOption> categoryOptions = <FilterOption>[
  FilterOption(id: 'cat-dairy', label: 'Süt ürünleri'),
  FilterOption(id: 'cat-grain', label: 'Bakliyat ve tahıl'),
  FilterOption(id: 'cat-meat', label: 'Et'),
  FilterOption(id: 'cat-oil', label: 'Yağ'),
  FilterOption(id: 'cat-electronics', label: 'Elektronik'),
  FilterOption(id: 'cat-tools', label: 'El aleti'),
];

/// The tag options the filter sheet offers. A tag is its own id.
const List<FilterOption> tagOptions = <FilterOption>[
  FilterOption(id: 'kahvaltı', label: 'kahvaltı'),
  FilterOption(id: 'soğuk zincir', label: 'soğuk zincir'),
  FilterOption(id: 'bakliyat', label: 'bakliyat'),
  FilterOption(id: 'sarf', label: 'sarf'),
];

/// Resolves a location id to its short label, for a filter chip.
String? resolveLocationLabel(String id) {
  for (final FilterOption option in locationOptions) {
    if (option.id == id) return option.label;
  }
  return null;
}

/// Resolves a location id to its full hierarchy path, for a detail row.
String? resolveLocationPath(String id) {
  for (final FilterOption option in locationOptions) {
    if (option.id == id) return option.fullPath;
  }
  return null;
}

/// Resolves a category id to its label, for a filter chip.
String? resolveCategoryLabel(String id) {
  for (final FilterOption option in categoryOptions) {
    if (option.id == id) return option.label;
  }
  return null;
}
