import '../../resources/views/products/product_fixtures.dart' show ProductListItem;

/// What a barcode read means for the shelf being counted.
///
/// **The three answers are the whole reason scanning needed its own endpoint**, and keeping them
/// apart here is what lets the screen behave differently for each without asking the server twice.
/// The list endpoint scopes by location, so a product that is the tenant's but sitting somewhere else
/// and a product the tenant has never owned both come back as an empty page there; they call for
/// opposite responses.
///
/// A pure classification over data the caller already holds, so every branch is reachable from a test
/// without a camera. That matters more than usual here: the camera cannot be driven in a headless
/// browser, so a design that folded this into the scanner widget would leave all three answers
/// verifiable only by hand on a device.
enum ScanVerdict {
  /// The record says this product is on the shelf being counted. Count it.
  onShelf,

  /// The tenant owns it and the record puts it elsewhere. The user is asked before it is counted
  /// here, because agreeing silently would move stock with a gesture that looks like a count.
  elsewhere,

  /// Nothing in the tenant's inventory carries this code. Collected rather than counted, and offered
  /// to the catalog flow once the count is over.
  unknown,
}

/// One read, classified, with whatever the lookup found.
class ScanOutcome {
  /// What the read means for this shelf.
  final ScanVerdict verdict;

  /// The product the code resolved to, absent only for [ScanVerdict.unknown].
  final ProductListItem? product;

  /// The code exactly as it was read, kept for the unknown queue and for the message a user sees.
  ///
  /// Not normalised: what the user needs to recognise is the number under the label they are holding,
  /// and the canonical fourteen-digit form is not what is printed there.
  final String code;

  /// Creates an outcome for [code].
  const ScanOutcome({required this.verdict, required this.code, this.product});

  /// Classifies a lookup against the shelf being counted.
  ///
  /// [locationIds] is where the record says the product is. A product with no stock anywhere resolves
  /// to [ScanVerdict.elsewhere] rather than to `onShelf`, and that is deliberate: the shelf's count
  /// list holds what the record says is here, so a product holding nothing is not on it, and counting
  /// it here without asking would be inbound stock wearing a count's clothes.
  factory ScanOutcome.of({
    required String code,
    required ProductListItem? product,
    required String shelfId,
  }) {
    if (product == null) {
      return ScanOutcome(verdict: ScanVerdict.unknown, code: code);
    }

    return ScanOutcome(
      verdict: product.locationIds.contains(shelfId) ? ScanVerdict.onShelf : ScanVerdict.elsewhere,
      code: code,
      product: product,
    );
  }
}
