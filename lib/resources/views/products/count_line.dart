import 'package:flutter/foundation.dart';
import 'package:magic/magic.dart';

import 'product_fixtures.dart';

// The count's domain types, split out of `count_fixtures.dart` because `no_hardcoded_copy_test`
// SKIPS any path containing `fixtures`, while these carry production, user-visible copy.
//
// That exemption is right for demo rows: a fixture product name stands in for a user's own and is not
// translated. It is also exactly how `CountLine.verdict` shipped as hardcoded Turkish, and why no
// gate could catch it. The string was never a literal the guard rejected; the guard never opened the
// file. Routing the verdict through `Lang.get` fixed the symptom; this is the hole it fell through.
//
// **The destination matters as much as the name, and the first attempt got it wrong.** These types
// went to `lib/app/models/` first, which is where a domain model belongs and which the scan does not
// reach: its roots are `lib/resources/views` and `lib/ui/components`. Putting the literal back and
// watching the test PASS is what caught it. So they sit beside `product_fixtures.dart` instead, which
// is also where their sibling type `ProductListItem` lives.
//
// That same exemption still covers `product_fixtures.dart` itself, which holds `ProductListItem` and
// is production code by the same argument. Nothing has fallen into it, checked rather than assumed:
// `expiryLabelFor` and the lot and serial labels all resolve through `Lang.get`. Moving that type is a
// change across about twenty importers and belongs on its own.

/// What the server did with one counted line.
///
/// Mirrors `App\Enums\CountOutcome`. Three of the four write no movement, and the client has to tell
/// them apart: a matched row is finished, a row needing a date is not, and both come back with an
/// empty movement list.
enum CountOutcome {
  /// The difference is in the ledger.
  written,

  /// The count agreed, so nothing was appended (D59).
  matched,

  /// More was found than recorded, with no sealed batch at that location to take a date from. Stock
  /// entry owns this row, because it asks for the date.
  needsDate,

  /// A serial-tracked product, counted by reading its units rather than by typing a number.
  serialTracked,
}

/// One line's answer from the count endpoint.
@immutable
class CountResult {
  /// Which product this answers for.
  final String productId;

  /// What happened.
  final CountOutcome outcome;

  /// Counted minus recorded, in base units, signed.
  ///
  /// Carried even when nothing was written, because a deferred row's whole message is "we found one
  /// more than the record and cannot date it" and that sentence needs the number. Recomputing it here
  /// would be a second implementation of arithmetic the server just did.
  final num delta;

  /// Creates a [CountResult].
  const CountResult({required this.productId, required this.outcome, required this.delta});

  /// Whether this row still needs the user to do something.
  bool get isUnfinished =>
      outcome == CountOutcome.needsDate || outcome == CountOutcome.serialTracked;
}

/// The outcome of committing a whole count.
@immutable
class CountCommit {
  /// Why the request failed, or null when it landed.
  ///
  /// A per-LINE refusal is not a failure and never sets this: the endpoint commits every writable
  /// line and names the rest, so a shelf with one unfinished row still saves the other thirty-nine.
  final String? error;

  /// One entry per submitted line, empty when [error] is set.
  final List<CountResult> lines;

  /// Creates a [CountCommit].
  const CountCommit({this.error, this.lines = const <CountResult>[]});

  /// The whole request failed.
  const CountCommit.failed(String message) : this(error: message);

  /// The request landed, with one answer per line.
  const CountCommit.landed(List<CountResult> lines) : this(lines: lines);

  /// The rows the user still has to finish.
  List<CountResult> get unfinished => lines.where((r) => r.isUnfinished).toList(growable: false);

  /// How many lines actually appended a movement.
  int get writtenCount => lines.where((r) => r.outcome == CountOutcome.written).length;
}

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

  /// Whether the content unit is genuinely FINER than the base unit.
  ///
  /// D26's whole-plus-remainder split only means something when one base unit contains many inner
  /// ones: a 1 lt carton counted in `adet` holds 1000 `ml`, so half of it is "500 ml" and nobody has
  /// to verify "1,5 adet" against a shelf.
  ///
  /// **A product whose base unit IS its content unit is the opposite case**, and the demo tenant has
  /// one: milk with a base unit of `l` and a content of `1 l`. There the inner amount is not a count
  /// of small units, it is the same decimal, so [figure] rounded it to a whole and printed 7.5 l as
  /// "7 l + 1 l", which reads as 8. The remainder field is a duplicate of the main one too.
  ///
  /// A decimal is the right form here rather than a violation of D26: the objection is to a
  /// COUNTABLE unit ("1,5 adet"), and 7.5 litres is exactly how a measured quantity is stated.
  bool get hasFinerContent {
    final num? content = product.contentAmount;

    return product.contentUnit != null && content != null && content > 1;
  }

  /// A base-unit figure written the way D26 requires: a whole count and an open remainder,
  /// never one decimal. `1.5` becomes `1 adet + 500 ml`, because nobody can verify "1,5
  /// adet" against a shelf.
  ///
  /// One formatter, used by the row's verdict AND by the summary, so the two can never
  /// disagree about the same number.
  String figure(num value) {
    // A measured unit with no finer content inside it: state the decimal rather than inventing a
    // split. See [hasFinerContent] for the number this printed before.
    if (!hasFinerContent) return '${ProductListItem.format(value)} ${product.unit}';

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
  ///
  /// **Four keys rather than one sentence assembled from fragments.** An earlier version built
  /// "Sistemde X · Y eksik" by concatenating a translated direction word, which reads as one string in
  /// Turkish and cannot be reordered for a language that puts the comparison first. Each verdict is a
  /// whole sentence with its own placeholders.
  String get verdict {
    if (!isCounted) return Lang.get('screens.stock_take.verdict_uncounted');

    final String system = figure(expected);

    if (isMatched) {
      return Lang.get('screens.stock_take.verdict_matched', {'system': system});
    }

    final num diff = variance!;

    return Lang.get(
      diff > 0 ? 'screens.stock_take.verdict_over' : 'screens.stock_take.verdict_short',
      {'system': system, 'diff': figure(diff.abs())},
    );
  }
}

/// What the system expects to find in one location.
///
/// **The projection first, because that is the figure a count is checking itself against.** The list
/// endpoint sends `product_stock` per (product, location) and never sends lots, so on real data this
/// is the only source that exists, and it is the server's own answer rather than a second derivation
/// of it.
///
/// The fallback is for a fixture and for a serial-tracked product, neither of which carries a
/// projection: `amountAt` sums LOTS, which is right for a product that has them and returns zero for
/// one that does not, so a lot-less product falls back to its whole balance. **That last step is only
/// valid because a lot-less fixture sits in exactly one location**, and `test/stock_take_test.dart`
/// asserts it rather than trusting it: two locations with no lots to split them would report the
/// entire balance in both places.
num expectedAt(ProductListItem product, String locationId) {
  final num? projected = product.locationAmounts[locationId];

  if (projected != null) return projected;

  return product.lots.isEmpty ? product.amount : product.amountAt(locationId);
}
