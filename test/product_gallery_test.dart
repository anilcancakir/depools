import 'package:depools/resources/views/products/product_fixtures.dart';
import 'package:depools/ui/components/product_gallery/product_gallery.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
// `show`, because magic's barrel re-exports a `TextDirection` of its own (wind's) that shadows the
// framework one `Directionality` needs here.
import 'package:magic/magic.dart' show WindTheme;

/// The gallery, from the payload to the row that draws it.
///
/// The interesting assertions are the two that carry a rule rather than a field: exactly one picture
/// is marked, and a credit that appears on several pictures is said once.
void main() {
  Map<String, dynamic> image(String id, {bool primary = false, String? credit}) {
    return <String, dynamic>{
      'id': id,
      'url': 'https://cdn.example.com/$id.jpg',
      'attribution': credit,
      'is_primary': primary,
      'position': 0,
    };
  }

  Widget wrap(Widget child) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: WindTheme(child: child),
    );
  }

  group('the payload becomes pictures', () {
    test('a product carries its gallery, primary marked', () {
      final ProductListItem product = ProductListItem.fromApi(
        <String, dynamic>{
          'id': 'p1',
          'name': 'Nutella 400 g',
          'base_unit': 'C62',
          'quantity': '4.000',
          'locations': const <Map<String, dynamic>>[],
          'images': <Map<String, dynamic>>[image('a', primary: true), image('b')],
        },
        locationLabels: const <String, String>{},
      );

      expect(product.images, hasLength(2));
      expect(product.images.first.isPrimary, isTrue);
      expect(product.images.last.isPrimary, isFalse);
    });

    test('a LIST payload carries none, which is the server withholding them', () {
      // `whenLoaded` on the resource: thirty rows do not fetch every picture of each to draw one.
      // An empty gallery here is the absence of the key, not a product without pictures, and the
      // detail screen is the only place that can tell.
      final ProductListItem product = ProductListItem.fromApi(
        <String, dynamic>{
          'id': 'p1',
          'name': 'Nutella 400 g',
          'base_unit': 'C62',
          'quantity': '4.000',
          'locations': const <Map<String, dynamic>>[],
        },
        locationLabels: const <String, String>{},
      );

      expect(product.images, isEmpty);
    });
  });

  group('the gallery draws them', () {
    testWidgets('one credit is said once however many pictures carry it', (WidgetTester tester) async {
      // A licence asks for the credit to be VISIBLE, not adjacent, and the same sentence under every
      // thumbnail is noise that makes it less readable rather than more.
      await tester.pumpWidget(
        wrap(
          const ProductGallery(
            name: 'Nutella 400 g',
            addLabel: 'Add',
            pictures: <GalleryPicture>[
              (id: 'a', url: 'https://cdn.example.com/a.jpg', attribution: 'OFF, CC-BY-SA', isPrimary: true),
              (id: 'b', url: 'https://cdn.example.com/b.jpg', attribution: 'OFF, CC-BY-SA', isPrimary: false),
            ],
          ),
        ),
      );

      expect(find.text('OFF, CC-BY-SA'), findsOneWidget);
    });

    testWidgets('an upload carries no credit, so nothing is printed', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(
          const ProductGallery(
            name: 'Nutella 400 g',
            addLabel: 'Add',
            pictures: <GalleryPicture>[
              (id: 'a', url: 'https://cdn.example.com/a.jpg', attribution: null, isPrimary: true),
            ],
          ),
        ),
      );

      expect(find.byType(Text), findsNothing);
    });
  });
}
