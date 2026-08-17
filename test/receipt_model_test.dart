import 'dart:typed_data';

import 'package:depools/app/controllers/receipt_controller.dart';
import 'package:depools/app/models/receipt.dart';
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
      expect(receipt.linesCount, isNull, reason: 'the detail endpoint never sends this key');
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
        reason: 'an unknown resolution string degrades to the state that claims nothing',
      );
      expect(unresolved.productName, isNull);
      expect(unresolved.rawUnitCode, 'XYZ', reason: 'D97: the raw code travels beside the map miss');
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
        XFile.fromData(Uint8List.fromList(const <int>[1, 2, 3]), name: 'receipt.jpg'),
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
          data: const <String, dynamic>{'message': 'This picture holds too many pixels to process.'},
        ),
      );

      final ReceiptUploadOutcome outcome = await ReceiptController().upload(
        XFile.fromData(Uint8List.fromList(const <int>[1, 2, 3]), name: 'receipt.jpg'),
      );

      expect(outcome.succeeded, isFalse);
      expect(outcome.message, 'This picture holds too many pixels to process.');
      expect(outcome.isDuplicate, isFalse);
    });

    test('a 409 is answered rather than treated as a failure, with the existing receipt', () async {
      // `ReceiptController::duplicate` sends only `data`, no `message` key (see the backend
      // controller's own docblock), so the client's fallback sentence is what actually reaches the
      // caller here. That fallback is a reserved, not-yet-catalogued key (Step 7 owns the copy), and
      // under the test binding an uncatalogued key renders as itself.
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
        XFile.fromData(Uint8List.fromList(const <int>[1, 2, 3]), name: 'receipt.jpg'),
      );

      expect(outcome.succeeded, isFalse);
      expect(outcome.message, 'screens.receipt.duplicate');
      expect(outcome.isDuplicate, isTrue);
      expect(outcome.duplicate?.id, 'r-existing');
    });
  });
}
