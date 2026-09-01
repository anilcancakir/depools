import 'dart:typed_data';

import 'package:depools/app/controllers/product_draft_controller.dart';
import 'package:depools/app/models/product_draft.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';

/// What `ProductDraftController` does with each shape `products/recognise` answers with.
///
/// The payloads mirror `backend/tests/Feature/ProductRecogniseTest.php`'s own assertions rather than
/// an imagined shape, so a change to the resource fails here rather than on a screen.
///
/// Constructed directly rather than through `.instance`, the same way the receipt controller's tests
/// do it: the singleton would carry state between tests, and what is under test is the controller
/// rather than the container.
void main() {
  tearDown(Http.unfake);

  XFile photo() => XFile.fromData(
    Uint8List.fromList(const <int>[1, 2, 3]),
    name: 'product.jpg',
  );

  /// Answers `products/recognise` with [card] and everything else with an empty list.
  ///
  /// The empty list matters: `begin` also fetches the unit vocabulary, and a fake that answered
  /// every url with the card would put a product payload where a list of units belongs.
  void fakeRead(Map<String, dynamic> card, {int status = 200}) {
    Http.fake(
      (MagicRequest request) => request.url.contains('recognise')
          ? MagicResponse(statusCode: status, data: <String, dynamic>{'data': card})
          : MagicResponse(
              statusCode: 200,
              data: const <String, dynamic>{'data': <dynamic>[]},
            ),
    );
  }

  Map<String, dynamic> card(Map<String, dynamic> overrides) => <String, dynamic>{
    'found': true,
    'cached': false,
    'outcome': 'succeeded',
    'image_phash': '0000000000000000c3a5f0e1d2b47896',
    'name': 'Süt Tam Yağlı 1 L',
    'brand': 'Pınar',
    'description': null,
    'category_id': null,
    'category_label': null,
    'unit': 'C62',
    ...overrides,
  };

  test('the card is on screen before the read even starts', () async {
    fakeRead(card(const <String, dynamic>{}));

    final ProductDraftController controller = ProductDraftController()
      ..begin(photo());

    // Criterion 2: a draft within a second, before the model responds. `begin` publishes
    // synchronously, so this assertion runs with no `await` between it and the call.
    expect(controller.draft, isNotNull);
    expect(controller.reading, isTrue);
    expect(controller.draft!.name, isNull);
  });

  test('a successful read fills the draft and stops the skeletons', () async {
    fakeRead(card(const <String, dynamic>{}));

    final ProductDraftController controller = ProductDraftController()
      ..begin(photo());
    await controller.read();

    expect(controller.reading, isFalse);
    expect(controller.error, isNull);

    final ProductDraft draft = controller.draft!;
    expect(draft.name, 'Süt Tam Yağlı 1 L');
    expect(draft.brand, 'Pınar');
    expect(draft.unit, 'C62');
    expect(draft.imagePhash, '0000000000000000c3a5f0e1d2b47896');
  });

  test('no credit is a draft the user can still type into, not an error', () async {
    fakeRead(card(const <String, dynamic>{
      'found': false,
      'outcome': 'no_credit',
      'name': null,
      'brand': null,
      'unit': null,
    }));

    final ProductDraftController controller = ProductDraftController()
      ..begin(photo());
    await controller.read();

    // Criterion 5: manual creation works end to end with zero credits. An error here would put the
    // screen into its failure branch over a state that is not a failure.
    expect(controller.error, isNull);
    expect(controller.draft!.recognised, isFalse);
    expect(controller.draft!.outcome, 'no_credit');
  });

  test('a refused upload leaves the sentence the server sent', () async {
    fakeRead(const <String, dynamic>{}, status: 422);
    Http.fake(
      (MagicRequest request) => MagicResponse(
        statusCode: 422,
        data: const <String, dynamic>{
          'message': 'This picture holds too many pixels to process.',
        },
      ),
    );

    final ProductDraftController controller = ProductDraftController()
      ..begin(photo());
    await controller.read();

    expect(controller.reading, isFalse);
    expect(controller.error, 'This picture holds too many pixels to process.');
  });

  test('saving posts the card and then the photograph', () async {
    final List<String> urls = <String>[];

    Http.fake((MagicRequest request) {
      urls.add(request.url);

      return request.url.contains('recognise')
          ? MagicResponse(
              statusCode: 200,
              data: <String, dynamic>{'data': card(const <String, dynamic>{})},
            )
          : MagicResponse(
              statusCode: 201,
              data: const <String, dynamic>{
                'data': <String, dynamic>{'id': 'p-1'},
              },
            );
    });

    final ProductDraftController controller = ProductDraftController()
      ..begin(photo());
    await controller.read();

    expect(await controller.save(), 'p-1');

    // The gallery upload is a second request rather than part of the create, because the create
    // takes JSON and a picture does not. Its order matters: the product has to exist first.
    expect(urls.where((String url) => url.contains('/products')).toList(), <String>[
      '/products/recognise',
      '/products',
      '/products/p-1/images',
    ]);
  });

  test('a card with no name does not reach the server at all', () async {
    fakeRead(card(const <String, dynamic>{
      'found': false,
      'outcome': 'schema_invalid',
      'name': null,
    }));

    final ProductDraftController controller = ProductDraftController()
      ..begin(photo());
    await controller.read();

    // D32 makes the name the one required field, so an empty one is not a request worth making: the
    // server would answer 422 about a field the screen already knows is missing.
    expect(await controller.save(), isNull);
  });

  test('a failed save keeps the draft so nothing the user typed is lost', () async {
    Http.fake(
      (MagicRequest request) => request.url.contains('recognise')
          ? MagicResponse(
              statusCode: 200,
              data: <String, dynamic>{'data': card(const <String, dynamic>{})},
            )
          : MagicResponse(
              statusCode: 422,
              data: const <String, dynamic>{'message': 'SKU already taken.'},
            ),
    );

    final ProductDraftController controller = ProductDraftController()
      ..begin(photo());
    await controller.read();

    expect(await controller.save(), isNull);
    expect(controller.error, 'SKU already taken.');
    expect(controller.saving, isFalse);
    expect(controller.draft!.name, 'Süt Tam Yağlı 1 L');
  });
}
