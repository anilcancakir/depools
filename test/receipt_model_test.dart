import 'dart:typed_data';

import 'package:depools/app/controllers/receipt_controller.dart';
import 'package:depools/app/models/location_node.dart';
import 'package:depools/app/models/receipt.dart';
import 'package:depools/app/models/shopping_line.dart';
import 'package:depools/ui/components/receipt_line_row/receipt_line_row.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';

/// Parsing `ReceiptResource`/`ReceiptLineResource`, and what `ReceiptController.upload` does with
/// each shape the endpoint answers with.
///
/// The literal payloads below mirror `backend/tests/Feature/ReceiptReadTest.php`'s own assertions
/// rather than an imagined shape: a matched line carrying `product_name`, an unresolved one carrying
/// null, and a decimal travelling as the STRING PostgreSQL actually sends (`'2.000'`, not `2`).
void main() {
  tearDown(Http.unfake);

  group('strict fill guards mass assignment', () {
    // One pair per promoted model (step 12). Each pair pins BOTH halves of the guard, and it takes
    // both, which a mutation run proved: `fill(strict: true)` throws on the FIRST offending key
    // (`model.dart:445-452`), so a test that only asserts `throwsA(isA<MassAssignmentException>())`
    // over a payload carrying one legal and one illegal key still passes after the legal key is
    // removed from `fillable`. The exception simply fires on a different key and the matcher cannot
    // tell the two causes apart. So the refusal case names the ATTRIBUTE it expects, and a second
    // case fills the whole declared list and expects no throw at all. Remove any entry from a
    // `fillable` below and one of the two goes red.

    test('ShoppingLine refuses a key outside StoreShoppingListItemRequest/UpdateShoppingListItemRequest', () {
      final ShoppingLine line = ShoppingLine();

      expect(
        () => line.fill(<String, dynamic>{
          'name': 'Bulaşık deterjanı',
          // `reason` is server-computed (D98): no endpoint accepts it from the client.
          'reason': 'manual',
        }, strict: true),
        throwsA(
          isA<MassAssignmentException>()
              .having((MassAssignmentException e) => e.attribute, 'attribute', 'reason'),
        ),
      );
    });

    test('ShoppingLine accepts exactly the keys its two FormRequests declare', () {
      expect(
        () => ShoppingLine().fill(<String, dynamic>{
          'product_id': 'p-1',
          'name': 'Bulaşık deterjanı',
          'quantity': 2,
          'unit': 'piece',
          'is_checked': false,
        }, strict: true),
        returnsNormally,
      );
    });

    test('LocationNode refuses a key outside StoreLocationRequest', () {
      final LocationNode node = LocationNode();

      expect(
        () => node.fill(<String, dynamic>{
          'name': 'Kiler',
          // `stock_count` is derived from the ledger, never accepted from a create request.
          'stock_count': 4,
        }, strict: true),
        throwsA(
          isA<MassAssignmentException>()
              .having((MassAssignmentException e) => e.attribute, 'attribute', 'stock_count'),
        ),
      );
    });

    test('LocationNode accepts exactly the keys StoreLocationRequest declares', () {
      expect(
        () => LocationNode().fill(<String, dynamic>{
          'name': 'Kiler',
          'parent_id': 'l-1',
          'icon': 'kitchen',
          'colour': 'teal',
        }, strict: true),
        returnsNormally,
      );
    });

    test('ReceiptLine refuses a key outside CommitReceiptRequest\'s per-line shape', () {
      final ReceiptLine line = ReceiptLine();

      expect(
        () => line.fill(<String, dynamic>{
          'product_id': 'p-1',
          // `resolution` is the resolver's own answer; a commit never overwrites it directly.
          'resolution': 'matched',
        }, strict: true),
        throwsA(
          isA<MassAssignmentException>()
              .having((MassAssignmentException e) => e.attribute, 'attribute', 'resolution'),
        ),
      );
    });

    test('ReceiptLine accepts exactly the keys CommitReceiptRequest declares per line', () {
      expect(
        () => ReceiptLine().fill(<String, dynamic>{
          'product_id': 'p-1',
          'quantity': 3,
        }, strict: true),
        returnsNormally,
      );
    });

    test('Receipt refuses every key, because nothing on it is client-writable in this slice', () {
      final Receipt receipt = Receipt();

      // `fillable` is empty: `StoreReceiptRequest` validates only the multipart `image`, never a
      // JSON attribute of the receipt itself, so every key is outside it by construction. This one
      // needs no positive case, because there is no key that would pass.
      expect(
        () => receipt.fill(<String, dynamic>{'supplier_name': 'Migros'}, strict: true),
        throwsA(
          isA<MassAssignmentException>()
              .having((MassAssignmentException e) => e.attribute, 'attribute', 'supplier_name'),
        ),
      );
    });
  });

  group('Receipt.fromApi', () {
    test('a detail payload parses every field, in printed line order', () {
      final Receipt receipt = Receipt.fromApi(<String, dynamic>{
        'id': 'r-1',
        'kind': 'fis',
        'status': 'pending',
        // Every extracted field is null on this slice, and that is the normal state: nothing has
        // read the document yet.
        'issued_on': null,
        'total_amount': null,
        'currency': null,
        'supplier_name': null,
        'confirmed_at': null,
        'created_at': '2026-08-15T09:00:00+00:00',
        'lines': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'line-1',
            'line_number': 1,
            'raw_name': 'PNR SUT 1LT',
            // PostgreSQL's `decimal(12,3)` arrives as a string, never as a bare number.
            'quantity': '2.000',
            'resolved_unit': 'C62',
            'raw_unit_code': 'C62',
            'unit_price': '17.4500',
            'line_total': '34.90',
            'resolution': 'matched',
            'resolved_by': 'alias',
            'product_id': 'p-1',
            'product_name': 'Pınar Süt Tam Yağlı 1 lt',
            'confidence': 92,
            'confirmed_at': null,
          },
          <String, dynamic>{
            'id': 'line-2',
            'line_number': 2,
            'raw_name': 'ORG KEM TAV',
            'quantity': '1.000',
            'resolved_unit': null,
            'raw_unit_code': 'XYZ',
            'unit_price': null,
            'line_total': null,
            // An unrecognised value: nothing in `data-model.md`'s vocabulary sends this, but the
            // client must not throw on a server it does not fully trust.
            'resolution': 'something_new',
            'resolved_by': null,
            'product_id': null,
            'product_name': null,
            'confidence': null,
            'confirmed_at': null,
          },
        ],
      });

      expect(receipt.id, 'r-1');
      expect(receipt.kind, 'fis');
      expect(receipt.status, 'pending');
      expect(receipt.issuedOn, isNull);
      expect(receipt.totalAmount, isNull);
      expect(receipt.currency, isNull);
      expect(receipt.supplierName, isNull);
      expect(receipt.createdAt, DateTime.parse('2026-08-15T09:00:00+00:00'));
      expect(
        receipt.linesCount,
        isNull,
        reason: 'the detail endpoint never sends this key',
      );
      expect(receipt.lines, hasLength(2));

      final ReceiptLine matched = receipt.lines[0];
      expect(matched.lineNumber, 1);
      expect(matched.rawName, 'PNR SUT 1LT');
      expect(matched.quantity, 2);
      expect(matched.unitPrice, 17.45);
      expect(matched.lineTotal, 34.90);
      expect(matched.resolution, LineResolution.matched);
      expect(matched.resolvedBy, ReceiptResolvedBy.alias);
      expect(matched.productId, 'p-1');
      expect(matched.productName, 'Pınar Süt Tam Yağlı 1 lt');
      expect(matched.confidence, 92);

      final ReceiptLine unresolved = receipt.lines[1];
      expect(
        unresolved.resolution,
        LineResolution.unresolved,
        reason:
            'an unknown resolution string degrades to the state that claims nothing',
      );
      expect(unresolved.productName, isNull);
      expect(
        unresolved.rawUnitCode,
        'XYZ',
        reason: 'D97: the raw code travels beside the map miss',
      );
      expect(unresolved.resolvedUnit, isNull);
    });

    test('a list row carries a line count and no lines', () {
      final Receipt receipt = Receipt.fromApi(<String, dynamic>{
        'id': 'r-1',
        'kind': 'fis',
        'status': 'pending',
        'issued_on': null,
        'total_amount': null,
        'currency': null,
        'supplier_name': null,
        'confirmed_at': null,
        'created_at': '2026-08-15T09:00:00+00:00',
        'lines_count': 2,
        // No `lines` key at all: `whenLoaded` drops it entirely on the list endpoint.
      });

      expect(receipt.linesCount, 2);
      expect(receipt.lines, isEmpty);
    });
  });

  group('ReceiptController.extract', () {
    /// A fake that answers the extract POST with [body] and the list GET with nothing.
    ///
    /// `extract` reloads the list on its way out, because the list row carries a line COUNT that a
    /// fresh read makes stale. So a fake answering only the POST would fail on the second request.
    void serve(Map<String, dynamic> body) {
      Http.fake((MagicRequest request) {
        return request.url.contains('/extract')
            ? MagicResponse(
                statusCode: 200,
                data: <String, dynamic>{'data': body},
              )
            : MagicResponse(
                statusCode: 200,
                data: const <String, dynamic>{'data': <dynamic>[]},
              );
      });
    }

    Map<String, dynamic> receipt({
      List<Map<String, dynamic>> lines = const <Map<String, dynamic>>[],
      String? outcome,
    }) {
      return <String, dynamic>{
        'id': 'r-1',
        'kind': 'fis',
        'status': lines.isEmpty ? 'pending' : 'extracted',
        'issued_on': null,
        'total_amount': null,
        'currency': null,
        'supplier_name': null,
        'confirmed_at': null,
        'created_at': '2026-09-01T10:00:00+00:00',
        'last_extraction_outcome': outcome,
        'lines': lines,
      };
    }

    test(
      'a read that produced nothing says so rather than redrawing the same card',
      () async {
        // **Measured in a browser before it was written here.** The request returned 200, the screen
        // redrew "not read yet", and the tap visibly did nothing: a successful request is not the
        // same as the user getting an answer, and this is the one path where the two come apart.
        //
        // `Lang.get` answers with the key under the plain test binding (nothing loads the catalogues),
        // which is what the upload tests below assert on too.
        serve(receipt());

        final String? message = await ReceiptController().extract('r-1');

        expect(message, 'screens.receipt.read_unreadable');
      },
    );

    test(
      'running out of credits is its own sentence, because it is actionable',
      () async {
        // Buying more or keying the lines in are both things the user can do. "Could not read it" is
        // not, and telling them the wrong one wastes the retry they would otherwise not attempt.
        serve(receipt(outcome: 'no_credit'));

        final String? message = await ReceiptController().extract('r-1');

        expect(message, 'screens.receipt.read_no_credit');
      },
    );

    test('a read that produced lines is silent', () async {
      serve(
        receipt(
          lines: <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'l-1',
              'line_number': 1,
              'raw_name': 'PNR SUT 1LT',
              'quantity': '2.000',
              'raw_unit_code': 'AD',
              'resolved_unit': 'H87',
              'unit_price': null,
              'line_total': null,
              'resolution': 'unresolved',
              'resolved_by': null,
              'product_id': null,
              'product_name': null,
              'confidence': 92,
              'confirmed_at': null,
            },
          ],
          outcome: 'succeeded',
        ),
      );

      final String? message = await ReceiptController().extract('r-1');

      expect(message, isNull);
    });
  });

  group('ReceiptController.upload', () {
    test('a 201 succeeds with no message and no duplicate', () async {
      Http.fake(
        (MagicRequest request) => MagicResponse(
          statusCode: 201,
          data: <String, dynamic>{
            'data': <String, dynamic>{
              'id': 'r-1',
              'kind': 'fis',
              'status': 'pending',
              'issued_on': null,
              'total_amount': null,
              'currency': null,
              'supplier_name': null,
              'confirmed_at': null,
              'created_at': '2026-08-15T09:00:00+00:00',
              'lines_count': 0,
            },
          },
        ),
      );

      final ReceiptUploadOutcome outcome = await ReceiptController().upload(
        XFile.fromData(
          Uint8List.fromList(const <int>[1, 2, 3]),
          name: 'receipt.jpg',
        ),
      );

      expect(outcome.succeeded, isTrue);
      expect(outcome.message, isNull);
      expect(outcome.duplicate, isNull);
    });

    test('a 422 fails with the server sentence', () async {
      // The server's own sentence lives in the JSON BODY (Laravel's validation-error shape), not in
      // `MagicResponse.message`, which the driver fills from the HTTP status line instead. Every
      // other write in this app reads `response['message']` for the same reason.
      Http.fake(
        (MagicRequest request) => MagicResponse(
          statusCode: 422,
          data: const <String, dynamic>{
            'message': 'This picture holds too many pixels to process.',
          },
        ),
      );

      final ReceiptUploadOutcome outcome = await ReceiptController().upload(
        XFile.fromData(
          Uint8List.fromList(const <int>[1, 2, 3]),
          name: 'receipt.jpg',
        ),
      );

      expect(outcome.succeeded, isFalse);
      expect(outcome.message, 'This picture holds too many pixels to process.');
      expect(outcome.isDuplicate, isFalse);
    });

    test(
      'a 409 is answered rather than treated as a failure, with the existing receipt',
      () async {
        // `ReceiptController::duplicate` sends only `data`, no `message` key (see the backend
        // controller's own docblock), so the sentence is always this app's own rather than a fallback
        // for one the server withheld. The key exists in both catalogues; nothing LOADS them under the
        // plain test binding, so `Lang.get` answers with the key itself and that is what to assert on.
        Http.fake(
          (MagicRequest request) => MagicResponse(
            statusCode: 409,
            data: <String, dynamic>{
              'data': <String, dynamic>{
                'id': 'r-existing',
                'kind': 'fis',
                'status': 'pending',
                'issued_on': null,
                'total_amount': null,
                'currency': null,
                'supplier_name': null,
                'confirmed_at': null,
                'created_at': '2026-08-10T09:00:00+00:00',
              },
            },
          ),
        );

        final ReceiptUploadOutcome outcome = await ReceiptController().upload(
          XFile.fromData(
            Uint8List.fromList(const <int>[1, 2, 3]),
            name: 'receipt.jpg',
          ),
        );

        expect(outcome.succeeded, isFalse);
        expect(outcome.message, 'screens.receipt.duplicate');
        expect(outcome.isDuplicate, isTrue);
        expect(outcome.duplicate?.id, 'r-existing');
      },
    );
  });
}
