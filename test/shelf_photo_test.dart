import 'package:depools/resources/views/products/shelf_fixtures.dart';
import 'package:depools/ui/components/receipt_line_row/receipt_line_row.dart' show LineResolution;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('shelf photo', () {
    test('region numbers are unique and contiguous from one', () {
      // The number is the ONLY link between a row and a box on the photograph (D60). A gap or
      // a duplicate would point a row at nothing, or two rows at the same box.
      final List<int> regions = shelfCandidates.map((c) => c.region).toList();
      expect(regions, List<int>.generate(shelfCandidates.length, (i) => i + 1));
    });

    test('boxes stay inside the photograph', () {
      for (final ShelfCandidate c in shelfCandidates) {
        expect(c.left + c.width, lessThanOrEqualTo(1.0), reason: 'region ${c.region} overflows');
        expect(c.top + c.height, lessThanOrEqualTo(1.0), reason: 'region ${c.region} overflows');
      }
    });

    test('the accept count is the settled count, not the region count', () {
      // Six regions, four products. A bulk-accept button labelled with the region count would
      // promise to write the unresolved bottle and the price label too.
      expect(shelfCandidates.length, 6);
      expect(settledCandidates.length, 4);
      expect(unresolvedCandidates.length, 1);
      expect(shelfCandidates.where((c) => c.resolution == LineResolution.rejected).length, 1);
    });

    test('the mid-read count never exceeds the region count', () {
      expect(resolvedSoFar, lessThanOrEqualTo(shelfCandidates.length));
    });
  });
}
