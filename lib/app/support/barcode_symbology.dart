import 'package:mobile_scanner/mobile_scanner.dart';

/// Which reader formats carry a GTIN, and therefore need no symbology sent with them.
///
/// **This is an API contract, not a convenience, which is why it is shared rather than copied.**
/// The server decides a barcode's identity by SHAPE: `Barcode::findForScan()` sends anything
/// digits-only to the `gtin` column whatever symbology it was given, so a GTIN recorded under
/// `(code, symbology)` becomes a row the cascade can never find again. That defect shipped in the
/// product-create path and was caught in review; the client half of the same rule lives here.
///
/// Two callers today, and a rule with two spellings is a rule that eventually disagrees with itself:
/// the count sheet reads a shelf and this reads a receiving bench, and both have to name a label the
/// same way for the same product to be one product.
const Set<BarcodeFormat> gtinBearingFormats = <BarcodeFormat>{
  BarcodeFormat.ean8,
  BarcodeFormat.ean13,
  BarcodeFormat.upcA,
  BarcodeFormat.upcE,
  BarcodeFormat.itf14,
};

/// The symbology name the API expects, or null for a format that carries a GTIN.
///
/// Lower-cased because the server stores it that way (`Barcode::normaliseSymbology()`), while the
/// enum's own name is camelCase. It is only sent for the formats where it is part of the identity:
/// the same digits read as an EAN-13 and as a UPC-A are ONE product, and saying which reader saw
/// them would split that product in two.
String? symbologyOf(BarcodeFormat format) =>
    gtinBearingFormats.contains(format) ? null : format.name.toLowerCase();
