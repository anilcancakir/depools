import 'package:depools/app/models/scan_entry.dart';
import 'package:depools/app/models/scan_source.dart';
import 'package:flutter_test/flutter_test.dart';

/// How a cascade answer becomes a row.
///
/// The mapping is the only part of the scan screen that can be wrong without looking wrong: every
/// value renders, and a row claiming more trust than the stage earned reads as a confident answer.
void main() {
  group('the stage a cascade answer names', () {
    test('the tenant\'s own product is authoritative', () {
      expect(ScanEntry.sourceOf('own'), ScanSource.own);
    });

    test('a community row is catalog, because somebody here confirmed it', () {
      expect(ScanEntry.sourceOf('community'), ScanSource.catalog);
    });

    test('an Open Food Facts row is unverified, because nobody here has', () {
      // Criterion 7 asks for exactly this to be visible. It is not a claim about OFF's accuracy,
      // which is better than a scrape: it is that no user of this app has confirmed the row.
      expect(ScanEntry.sourceOf('off'), ScanSource.unverified);
    });

    test('a stage this client has not heard of is not trusted upward', () {
      // The only direction that puts a wrong claim on screen is guessing toward `own`, so an
      // unknown value lands on the cautious side rather than the confident one.
      expect(ScanEntry.sourceOf('paid_lookup'), ScanSource.unverified);
      expect(ScanEntry.sourceOf(null), ScanSource.unverified);
    });
  });

  group('a row in a batch', () {
    test('an unmatched row is the only one that is not settled', () {
      for (final ScanSource source in ScanSource.values) {
        final ScanEntry entry = ScanEntry(
          barcode: '1',
          count: 1,
          source: source,
        );

        expect(
          entry.isSettled,
          source != ScanSource.unmatched,
          reason: source.name,
        );
      }
    });

    test('scanning the same carton again is a second unit', () {
      // The prior Anılcan set: two reads of one barcode mean two cartons, which is the whole
      // reason a receiving bench scans at all.
      const ScanEntry entry = ScanEntry(
        barcode: '869',
        count: 1,
        sequence: 3,
        productName: 'Süt',
      );

      final ScanEntry twice = entry.incremented(sequence: 7);

      expect(twice.count, 2);
      // Everything else survives, so an increment cannot quietly lose the resolution.
      expect(twice.productName, 'Süt');
      expect(twice.barcode, '869');
      // And it takes the NEW read's place, because a repeat is a scan: without this the sixth
      // yoghurt increments a row that has already scrolled out of sight (D40).
      expect(twice.sequence, 7);
    });
  });
}
