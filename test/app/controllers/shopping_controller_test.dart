import 'package:depools/app/controllers/shopping_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';

/// [ShoppingController.add]'s rule map, mirroring `StoreShoppingListItemRequest::rules()`.
void main() {
  tearDown(Http.unfake);

  test('a server refusal on name is readable through hasError/getError', () async {
    Http.fake(
      (MagicRequest request) => MagicResponse(
        statusCode: 422,
        data: const <String, dynamic>{
          'message': 'The given data was invalid.',
          'errors': <String, dynamic>{
            'name': <String>['The name field is required.'],
          },
        },
      ),
    );

    final ShoppingController controller = ShoppingController();

    final String? result = await controller.add('Washing-up liquid', 2);

    expect(result, isNotNull);
    expect(controller.hasError('name'), isTrue);
    expect(controller.getError('name'), isNotNull);
  });

  test('an empty name never reaches the server', () async {
    bool requested = false;

    Http.fake((MagicRequest request) {
      requested = true;

      return MagicResponse(statusCode: 200, data: const <String, dynamic>{'data': <dynamic>[]});
    });

    final ShoppingController controller = ShoppingController();

    final String? result = await controller.add('', 2);

    expect(requested, isFalse, reason: 'the client rule refuses this before any request is sent');
    expect(controller.hasError('name'), isTrue);
    expect(result, isNotNull);
  });
}
