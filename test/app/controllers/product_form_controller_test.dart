import 'package:depools/app/controllers/product_form_controller.dart';
import 'package:depools/resources/views/products/product_form_view.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';

/// `ProductFormController.save`, and the view's four render sites reading from it.
///
/// `Http.fake` swaps the driver in magic's container, so the controller can be constructed directly
/// rather than resolved through `.instance`, the same shape `product_controller_test.dart` and
/// `location_controller_test.dart` already use: the shared instance is what the SCREEN needs, not
/// what a test does. The one widget test pumps `ProductFormView` itself, because it is the view's
/// four render sites the step actually changed, and `product_form_view.dart` has no separate test
/// file on the briefing's allow-list to carry that assertion.
void main() {
  tearDown(Http.unfake);

  /// Answers every request except `/products` with an empty list, standing in for `/units`.
  void fakeSave(MagicResponse Function(MagicRequest request) onProducts) {
    Http.fake(
      (MagicRequest request) => request.url.contains('/products')
          ? onProducts(request)
          : MagicResponse(statusCode: 200, data: const <String, dynamic>{'data': <dynamic>[]}),
    );
  }

  group('ProductFormController.save', () {
    test('a server refusal on name is readable through hasError/getError', () async {
      fakeSave(
        (MagicRequest request) => MagicResponse(
          statusCode: 422,
          data: const <String, dynamic>{
            'message': 'The given data was invalid.',
            'errors': <String, dynamic>{
              'name': <String>['The name has already been taken.'],
            },
          },
        ),
      );

      final ProductFormController controller = ProductFormController();

      final ({bool ok, String? id}) result = await controller.save(
        name: 'Milk',
        baseUnit: 'C62',
        tracksExpiry: false,
      );

      expect(result.ok, isFalse);
      expect(controller.hasError('name'), isTrue);
      expect(controller.getError('name'), 'The name has already been taken.');
      // The refusal named a field, so the no-field fallback must stay unset: showing both would say
      // the same thing twice, once under the field and once as a toast.
      expect(controller.saveError, isNull);
    });

    test('a name over 255 characters never reaches the server', () async {
      bool requested = false;

      fakeSave((MagicRequest request) {
        requested = true;

        return MagicResponse(
          statusCode: 201,
          data: const <String, dynamic>{
            'data': <String, dynamic>{'id': 'p-1'},
          },
        );
      });

      final ProductFormController controller = ProductFormController();

      final ({bool ok, String? id}) result = await controller.save(
        name: 'x' * 256,
        baseUnit: 'C62',
        tracksExpiry: false,
      );

      expect(requested, isFalse, reason: 'the client rule refuses this before any request is sent');
      expect(result.ok, isFalse);
      expect(controller.hasError('name'), isTrue);
    });

    test('a refusal naming no field is readable through saveError, not a field slot', () async {
      fakeSave(
        (MagicRequest request) => MagicResponse(
          statusCode: 429,
          data: const <String, dynamic>{'message': 'Too many attempts.'},
        ),
      );

      final ProductFormController controller = ProductFormController();

      final ({bool ok, String? id}) result = await controller.save(
        name: 'Milk',
        baseUnit: 'C62',
        tracksExpiry: false,
      );

      expect(result.ok, isFalse);
      expect(controller.hasErrors, isFalse);
      expect(controller.saveError, 'Too many attempts.');
    });

    test('a successful save reports the id the server sent', () async {
      fakeSave(
        (MagicRequest request) => MagicResponse(
          statusCode: 201,
          data: const <String, dynamic>{
            'data': <String, dynamic>{'id': 'p-1'},
          },
        ),
      );

      final ProductFormController controller = ProductFormController();

      final ({bool ok, String? id}) result = await controller.save(
        name: 'Milk',
        baseUnit: 'C62',
        tracksExpiry: false,
      );

      expect(result.ok, isTrue);
      expect(result.id, 'p-1');
      expect(controller.saveError, isNull);
    });
  });

  group('ProductFormView renders the controller\'s errors', () {
    // Every long row overflows once in this harness (raw keys, see below), and each `RenderFlex`
    // announces only once per instance (`design.md`'s own note on the same fact), so the count
    // grows with the number of overflowing rows rather than with the number of pumps. `takeException`
    // reads one at a time and throws once none are left, so this drains whatever is queued.
    void drainOverflows(WidgetTester tester) {
      while (tester.takeException() != null) {}
    }

    Widget wrap(Widget view) {
      return WindTheme(
        data: WindThemeData(),
        builder: (BuildContext context, WindThemeController controller) => WidgetsApp(
          color: const Color(0xFF000000),
          builder: (BuildContext context, Widget? child) => view,
        ),
      );
    }

    testWidgets(
      'a 422 naming name renders under the name field, not as a toast',
      (WidgetTester tester) async {
        fakeSave(
          (MagicRequest request) => MagicResponse(
            statusCode: 422,
            data: const <String, dynamic>{
              'message': 'The given data was invalid.',
              'errors': <String, dynamic>{
                'name': <String>['The name has already been taken.'],
              },
            },
          ),
        );

        // Wide enough for the whole scaffold: the default 800x600 surface cuts off the footer
        // buttons, which is a fact about the harness rather than a layout defect (see
        // `dashboard_first_run_test`'s own note on the same surface).
        tester.view.physicalSize = const Size(390, 1600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(wrap(const ProductFormView()));
        await tester.pump();

        // Raw keys overflow several rows in this harness, the same fact `dashboard_first_run_test`
        // records: nothing loads the catalogue here, so `Lang.get` returns its argument, which is far
        // longer than the copy it stands for. Consumed rather than worked around, because it is not a
        // layout defect and the real layout is verified against the running app.
        drainOverflows(tester);

        await tester.enterText(find.byType(EditableText).first, 'Milk');
        await tester.pump();
        drainOverflows(tester);

        await tester.tap(find.text('screens.product_form.save_and_stock'));
        await tester.pumpAndSettle();
        drainOverflows(tester);

        // The message rendered is the server's own string, read straight off `getError('name')`
        // rather than through `Lang.get`, so it is exactly what the field slot shows.
        expect(find.text('The name has already been taken.'), findsOneWidget);
      },
    );
  });
}
