import 'package:depools/app/support/barcode_symbology.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Which reads carry a symbology to the API, and which must not.
///
/// **This pins a contract with the server, not a preference.** `Barcode::findForScan()` decides by
/// SHAPE: anything digits-only is looked up in the `gtin` column whatever symbology came with it. So
/// sending one for a GTIN-bearing format writes a row under `(code, symbology)` that no later scan
/// can find, and the same defect already shipped once in the product-create path.
void main() {
  group('a format that carries a GTIN sends no symbology', () {
    for (final BarcodeFormat format in <BarcodeFormat>[
      BarcodeFormat.ean8,
      BarcodeFormat.ean13,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.itf14,
    ]) {
      test(format.name, () {
        expect(symbologyOf(format), isNull);
      });
    }
  });

  group('a format that does not carries its own name', () {
    test('code128 is part of the label identity', () {
      // The same characters as Code128 and as a QR are two different labels, which is why the
      // server treats the symbology as part of the identity rather than as a hint.
      expect(symbologyOf(BarcodeFormat.code128), 'code128');
    });

    test('qrCode is lower-cased, because the server stores it that way', () {
      // `Barcode::normaliseSymbology()` is `mb_strtolower(trim())`, and the enum's own name is
      // camelCase, so an unlowered name would create a second row for the same label.
      expect(symbologyOf(BarcodeFormat.qrCode), 'qrcode');
      expect(symbologyOf(BarcodeFormat.dataMatrix), 'datamatrix');
    });
  });

  test('upcA and ean13 agree, which is the point of returning null', () {
    // The same carton read by two readers is ONE product. If either sent a symbology they would
    // land in different rows and the catalogue would hold the same milk twice.
    expect(symbologyOf(BarcodeFormat.upcA), symbologyOf(BarcodeFormat.ean13));
  });
}
