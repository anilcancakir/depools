import 'package:depools/resources/views/products/product_fixtures.dart';
import 'package:depools/ui/components/product_row/product_row.dart';
import 'package:depools/ui/components/product_thumb/product_thumb.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
// `show`, because magic's barrel re-exports a `TextDirection` of its own (wind's) that shadows the
// framework one `Directionality` needs here.
import 'package:magic/magic.dart' show WindTheme;

/// The product's own picture, from the API payload to the row that draws it.
///
/// Two halves that fail separately: the mapping can drop the field, and the row can accept it and
/// not pass it on. The scan screen already had a picture; a product the tenant owns is the one the
/// list is made of, and it showed the same photo glyph on every line.
void main() {
  group('a product carries its picture', () {
    Map<String, dynamic> payload(Object? imageUrl) {
      return <String, dynamic>{
        'id': 'p1',
        'name': 'Pınar Süt Tam Yağlı 1 lt',
        'base_unit': 'C62',
        'quantity': '4.000',
        'image_url': ?imageUrl,
        'locations': const <Map<String, dynamic>>[],
      };
    }

    test('the mapping keeps the url the payload sent', () {
      final ProductListItem product = ProductListItem.fromApi(
        payload('https://cdn.example.com/products/milk.jpg'),
        locationLabels: const <String, String>{},
      );

      expect(product.imageUrl, 'https://cdn.example.com/products/milk.jpg');
    });

    test('a product with no picture is null rather than blank', () {
      // The ordinary case, and it stays ordinary until upload exists: nothing writes a product's
      // image today, so most rows fall back to the initial.
      final ProductListItem product = ProductListItem.fromApi(
        payload(null),
        locationLabels: const <String, String>{},
      );

      expect(product.imageUrl, isNull);
    });

    testWidgets('the row hands it to the thumbnail it draws', (WidgetTester tester) async {
      // **Rendered rather than read back off the constructor.** Asserting `row.imageUrl` would have
      // passed with the field wired to nothing at all, which is the defect this is here to catch: a
      // row that accepts a url and keeps drawing the placeholder box looks identical from outside.
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: WindTheme(
            child: ProductRow(
              name: 'Pınar Süt Tam Yağlı 1 lt',
              amount: 4,
              formatted: '4',
              imageUrl: 'https://cdn.example.com/products/milk.jpg',
            ),
          ),
        ),
      );

      final ProductThumb thumb = tester.widget<ProductThumb>(find.byType(ProductThumb));

      expect(thumb.imageUrl, 'https://cdn.example.com/products/milk.jpg');
      expect(thumb.name, 'Pınar Süt Tam Yağlı 1 lt', reason: 'the initial comes from the name');
    });

    test('the skeleton has no picture to draw', () {
      // It is the row's own shadow, so it takes the same geometry from the same recipe and fills
      // none of it. A url here would mean a placeholder trying to load something.
      const ProductRow skeleton = ProductRow.skeleton();

      expect(skeleton.imageUrl, isNull);
    });
  });
}
