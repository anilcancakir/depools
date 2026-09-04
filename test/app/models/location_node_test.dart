import 'package:depools/app/models/location_node.dart';
import 'package:flutter_test/flutter_test.dart';

/// Decoding `api/v1/locations`'s wire shape into [LocationNode].
///
/// **`fromApi` never nests children.** The endpoint returns one flat list (see
/// `LocationController`'s own docblock: "one flat list, ordered by path"), and the tree plus the
/// "N products, M sub-locations" summary are both assembled by the CALLER from that flat list: a
/// node counts its own children by scanning every row's `parent_id`, then hands the model a
/// `summarise` closure that already carries the answer. So there is no nested-map field for this
/// model to decode as [LocationNode] instances; a "node with children" here means a row whose
/// `summarise` closure was built from a non-zero child count, not a payload shape. `casts` is empty
/// on this model, so there is no cast type to assert beyond the plain field reads.
void main() {
  group('LocationNode.fromApi', () {
    test('a root row stores whatever its summarise closure computed for its children', () {
      // Standing in for what `LocationController._read` does: it counts sibling rows whose
      // `parent_id` matches this row's id and bakes that count into the closure before the model
      // ever sees it.
      final LocationNode node = LocationNode.fromApi(
        <String, dynamic>{
          'id': 'loc-1',
          'name': 'Kiler',
          'depth': 0,
          'stock_count': 4,
          'full_path': 'Kiler',
          'parent_id': null,
          'icon': 'dining',
          'colour': 'amber',
        },
        summarise: (int products) => '$products ürün · 3 alt konum',
      )!;

      expect(node.id, 'loc-1');
      expect(node.name, 'Kiler');
      expect(node.depth, 0);
      expect(node.productCount, 4);
      expect(node.summary, '4 ürün · 3 alt konum');
      expect(node.path, 'Kiler');
      expect(node.parentId, isNull);
      expect(node.icon, 'dining');
      expect(node.colour, 'amber');
    });

    test('a leaf row with no full_path falls back to its own name', () {
      final LocationNode node = LocationNode.fromApi(
        <String, dynamic>{
          'id': 'loc-2',
          'name': 'Raf 1',
          'depth': 1,
          'stock_count': 1,
          // No `full_path` key at all, which the real endpoint omits on a row with no ancestors sent.
          'parent_id': 'loc-1',
          'icon': null,
          'colour': null,
        },
        summarise: (int products) => '$products ürün',
      )!;

      expect(node.path, 'Raf 1', reason: 'falls back to the bare name when full_path is absent');
      expect(node.parentId, 'loc-1');
      expect(node.icon, isNull);
      expect(node.colour, isNull);
    });

    test('a negative depth clamps to zero rather than indenting backwards', () {
      final LocationNode node = LocationNode.fromApi(
        <String, dynamic>{
          'id': 'loc-3',
          'name': 'Depo',
          'depth': -1,
          'stock_count': 0,
          'parent_id': null,
        },
        summarise: (int products) => 'Boş',
      )!;

      expect(node.depth, 0);
    });

    test('a row with no id or a blank name cannot be read', () {
      expect(
        LocationNode.fromApi(
          <String, dynamic>{'id': null, 'name': 'Raf 2'},
          summarise: (int products) => '',
        ),
        isNull,
      );

      expect(
        LocationNode.fromApi(
          <String, dynamic>{'id': 'loc-4', 'name': '   '},
          summarise: (int products) => '',
        ),
        isNull,
      );
    });
  });
}
