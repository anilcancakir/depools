import 'package:depools/app/controllers/scan_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';

/// [ScanController.commit]'s rule map, mirroring `ReceiveStockBatchRequest::rules()`.
void main() {
  tearDown(Http.unfake);

  MagicResponse resolved() => MagicResponse(
    statusCode: 200,
    data: const <String, dynamic>{
      'data': <String, dynamic>{
        'name': 'Milk',
        'source': 'own',
        'product_id': 'p-1',
      },
    },
  );

  test('a server refusal on lines is readable through hasError/getError', () async {
    Http.fake(
      (MagicRequest request) => request.url.contains('/barcode/resolve')
          ? resolved()
          : MagicResponse(
              statusCode: 422,
              data: const <String, dynamic>{
                'message': 'The given data was invalid.',
                'errors': <String, dynamic>{
                  'lines': <String>['The lines field is required.'],
                },
              },
            ),
    );

    final ScanController controller = ScanController();
    await controller.scan('8690504010012');
    controller.chooseDestination('loc-1');

    final String? result = await controller.commit();

    expect(result, isNotNull);
    expect(controller.hasError('lines'), isTrue);
    expect(controller.getError('lines'), isNotNull);
  });
}
