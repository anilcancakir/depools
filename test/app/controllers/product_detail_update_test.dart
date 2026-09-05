import 'package:depools/app/controllers/product_detail_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';

/// `ProductDetailController.updateField`, the write four rows on the product screen offered and
/// never made.
///
/// The name, brand and SKU rows each opened `FieldEditorSheet` and threw the answer away: no
/// request, no error, no field. There was nothing to call either, since the API had no product
/// update until `PUT api/v1/products/{id}` landed beside these tests.
///
/// **One field per call, because the screen edits one row per sheet.** That is what makes `null`
/// unambiguous here: it is the clear, not an omission, and the endpoint's `sometimes` rules mean an
/// absent key is what leaves a field alone. A method taking every field at once would have needed a
/// second parameter to say which of its nulls were meant.
///
/// `Http.fake` swaps the driver in magic's container, so the controller is constructed directly
/// rather than resolved through `.instance`: the shared instance is what the SCREEN needs, not what
/// a test does.
void main() {
  tearDown(Http.unfake);

  const String id = '01a05da0-7c82-70fb-bfe4-73b962ef6ab9';

  /// A payload complete enough for the reload that follows a successful write.
  ///
  /// `base_unit` and `locations` are here because `updateField` calls `load(force: true)` on the way
  /// out, and a fixture thin enough to decode into nothing threw a cast error INSIDE the assertion,
  /// which passed anyway. A test whose noise can hide its own failure is worth the four extra keys.
  Map<String, dynamic> product({String name = 'Zeytinyağı'}) => <String, dynamic>{
    'data': <String, dynamic>{
      'id': id,
      'name': name,
      'base_unit': 'adet',
      'quantity': '1.000',
      'locations': <Map<String, dynamic>>[],
      'stock': <dynamic>[],
    },
  };

  group('the payload carries only the row that changed', () {
    test('a brand edit sends the brand and nothing else', () async {
      // The endpoint is partial by construction, and this is the half the client owes it: a payload
      // that also carried the untouched name and SKU would make every save a three-field write, so
      // a stale value on screen could overwrite a newer one from another device.
      MagicRequest? sent;

      Http.fake((MagicRequest request) {
        if (request.method == 'PUT') sent = request;

        return MagicResponse(statusCode: 200, data: product());
      });

      final String? failure = await ProductDetailController().updateField(id, 'brand', 'Kırkpınar');

      expect(failure, isNull);
      expect(sent?.data, <String, dynamic>{'brand': 'Kırkpınar'});
    });

    test('an empty answer clears the field rather than being dropped', () async {
      // "Leave it alone" and "empty it" have to be different requests or one of the two is
      // unreachable. One field per call is what makes the null mean the second without a flag.
      MagicRequest? sent;

      Http.fake((MagicRequest request) {
        if (request.method == 'PUT') sent = request;

        return MagicResponse(statusCode: 200, data: product());
      });

      await ProductDetailController().updateField(id, 'sku', '  ');

      expect(sent?.data, <String, dynamic>{'sku': null});
    });
  });

  group('the client refuses before the server has to', () {
    test('a blank name never reaches the wire', () async {
      bool put = false;

      Http.fake((MagicRequest request) {
        if (request.method == 'PUT') put = true;

        return MagicResponse(statusCode: 200, data: product());
      });

      final String? failure = await ProductDetailController().updateField(id, 'name', '');

      expect(failure, isNotNull);
      expect(put, isFalse, reason: 'a refusal the client can make itself costs no round trip');
    });

    test('a name past the column bound never reaches the wire', () async {
      bool put = false;

      Http.fake((MagicRequest request) {
        if (request.method == 'PUT') put = true;

        return MagicResponse(statusCode: 200, data: product());
      });

      final String? failure = await ProductDetailController().updateField(id, 'name', 'a' * 256);

      expect(failure, isNotNull);
      expect(put, isFalse);
    });

    test('a field with no rule set is refused rather than sent blindly', () async {
      // The view names the field, so a typo or a row wired to a column the endpoint does not accept
      // would otherwise reach the API and come back as a silent no-op: `validated()` returns only
      // what the rules name, so an unknown key is DROPPED server-side and the write looks like it
      // worked. Refusing here is what turns that into something a person can see.
      bool put = false;

      Http.fake((MagicRequest request) {
        if (request.method == 'PUT') put = true;

        return MagicResponse(statusCode: 200, data: product());
      });

      final String? failure = await ProductDetailController().updateField(id, 'category', 'Yağlar');

      expect(failure, isNotNull);
      expect(put, isFalse);
    });
  });

  test('a server refusal comes back as a sentence rather than silence', () async {
    Http.fake(
      (MagicRequest request) => MagicResponse(
        statusCode: 422,
        data: const <String, dynamic>{
          'message': 'The sku has already been taken.',
          'errors': <String, dynamic>{
            'sku': <String>['The sku has already been taken.'],
          },
        },
      ),
    );

    final String? failure = await ProductDetailController().updateField(id, 'sku', 'ZY-750');

    expect(failure, 'The sku has already been taken.');
  });

  test('a 500 answers with the screen copy, not the server body', () async {
    // The label screen printed a Node.js stack trace out of exactly this field, so a write path
    // added afterwards routes through `serverMessage` from the start.
    Http.fake(
      (MagicRequest request) => MagicResponse(
        statusCode: 500,
        data: const <String, dynamic>{'message': 'Error: Could not find Chrome at /srv/app/vendor'},
      ),
    );

    final String? failure = await ProductDetailController().updateField(id, 'name', 'Şeker');

    expect(failure, isNotNull);
    expect(failure, isNot(contains('/srv/app/vendor')));
  });
}
