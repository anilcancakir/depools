import 'package:depools/app/controllers/location_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';

/// [LocationController.create]'s rule map, mirroring `StoreLocationRequest::rules()`.
///
/// The name sent here passes the client-side rules (`Required`, `Max(255)`), so the request goes
/// out and the fake answers as the server would for a rule this client cannot mirror (`icon`'s
/// `Rule::exists`): the property under test is that a server-side 422 still lands on the field, via
/// `handleApiError`, not that the client itself refuses anything.
void main() {
  tearDown(Http.unfake);

  test('a server refusal on name is readable through hasError/getError', () async {
    Http.fake(
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

    final LocationController controller = LocationController();

    final String? result = await controller.create(name: 'Kitchen');

    expect(result, isNotNull);
    expect(controller.hasError('name'), isTrue);
    expect(controller.getError('name'), isNotNull);
  });

  test('a name over 255 characters never reaches the server', () async {
    bool requested = false;

    Http.fake((MagicRequest request) {
      requested = true;

      return MagicResponse(statusCode: 200, data: const <String, dynamic>{'data': <dynamic>{}});
    });

    final LocationController controller = LocationController();

    final String? result = await controller.create(name: 'x' * 256);

    expect(requested, isFalse, reason: 'the client rule refuses this before any request is sent');
    expect(controller.hasError('name'), isTrue);
    expect(result, isNotNull);
  });
}
