import 'dart:typed_data';

import 'package:depools/app/controllers/shelf_controller.dart';
import 'package:depools/app/models/shelf_read.dart';
import 'package:depools/ui/components/receipt_line_row/receipt_line_row.dart' show LineResolution;
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';

/// Parsing a `shelf-reads` payload, and what `ShelfController` does with each shape it answers with.
///
/// The payloads mirror `backend/tests/Feature/ShelfReadTest.php`'s own assertions rather than an
/// imagined shape: fractional boxes, a nullable name, a decimal-string quantity, and the outcome
/// beside the candidates.
void main() {
  tearDown(Http.unfake);

  XFile photo() => XFile.fromData(
    Uint8List.fromList(const <int>[1, 2, 3]),
    name: 'shelf.jpg',
  );

  Map<String, dynamic> candidate(Map<String, dynamic> overrides) => <String, dynamic>{
    'id': 'c1',
    'region': 1,
    'left': 0.1,
    'top': 0.2,
    'width': 0.3,
    'height': 0.4,
    'product_name': 'Pınar Süt 1 lt',
    'product_id': 'p1',
    'resolution': 'matched',
    'quantity': '2.000',
    'raw_unit_code': null,
    'unit': 'C62',
    'confirmed_at': null,
    ...overrides,
  };

  Map<String, dynamic> read(List<Map<String, dynamic>> candidates, {String? outcome}) =>
      <String, dynamic>{
        'id': 's1',
        'confirmed_at': null,
        'created_at': '2026-09-01T10:00:00+00:00',
        'has_document': true,
        'candidates': candidates,
        'last_read_outcome': outcome,
      };

  group('ShelfRead.fromApi', () {
    test('a region parses its box, its name and its count', () {
      final ShelfRead parsed = ShelfRead.fromApi(read([candidate(const <String, dynamic>{})]));

      final ShelfCandidate c = parsed.candidates.single;
      expect(c.region, 1);
      expect(c.left, 0.1);
      expect(c.height, 0.4);
      expect(c.productName, 'Pınar Süt 1 lt');
      // A decimal STRING on the wire, because it reaches the ledger and PostgreSQL sends `'2.000'`.
      expect(c.quantity, 2);
      expect(c.isSettled, isTrue);
    });

    test('a region the model could not name is unresolved and keeps its box', () {
      final ShelfRead parsed = ShelfRead.fromApi(read([
        candidate(const <String, dynamic>{
          'product_name': null,
          'product_id': null,
          'resolution': 'unresolved',
          'quantity': null,
        }),
      ]));

      final ShelfCandidate c = parsed.candidates.single;
      expect(c.productName, isNull);
      // Null rather than zero: printing `0` would claim the shelf held none rather than that the app
      // could not tell, which is the difference between a review the user can check and one they
      // have to distrust.
      expect(c.quantity, isNull);
      expect(c.isUnresolved, isTrue);
      expect(c.left, 0.1);
    });

    test('a box outside the frame is clamped rather than placed off the picture', () {
      final ShelfRead parsed = ShelfRead.fromApi(read([
        candidate(const <String, dynamic>{'left': 1.4, 'top': -0.2}),
      ]));

      // The server refuses an out-of-frame box before storing one, so this is a parser's guard: a
      // value that arrived broken would place a `Positioned` child off the picture and take the
      // whole `Stack` with it.
      expect(parsed.candidates.single.left, 1);
      expect(parsed.candidates.single.top, 0);
    });

    test('the settled count is not the region count', () {
      final ShelfRead parsed = ShelfRead.fromApi(read([
        candidate(const <String, dynamic>{'region': 1}),
        candidate(const <String, dynamic>{'region': 2, 'resolution': 'unresolved', 'product_id': null}),
        candidate(const <String, dynamic>{'region': 3, 'resolution': 'rejected', 'product_id': null}),
      ]));

      // D60: a button labelled with the region count would promise to write an unnamed bottle and a
      // price label the recogniser mistook for stock.
      expect(parsed.candidates.length, 3);
      expect(parsed.settled.length, 1);
      expect(parsed.unresolved.length, 1);
    });

    test('an unreadable resolution falls back to unresolved rather than to matched', () {
      final ShelfRead parsed = ShelfRead.fromApi(read([
        candidate(const <String, dynamic>{'resolution': 'something-new'}),
      ]));

      // The safe default is the one that ASKS. Falling back to `matched` would silently write stock
      // for a state this build does not understand.
      expect(parsed.candidates.single.resolution, LineResolution.unresolved);
    });
  });

  group('decisions', () {
    final ShelfRead parsed = ShelfRead.fromApi(read([
      candidate(const <String, dynamic>{'region': 1}),
      candidate(const <String, dynamic>{'region': 2, 'resolution': 'unresolved', 'product_id': null}),
    ]));

    test('accepting one region leaves the other alone', () {
      final ShelfCandidate answered =
          parsed.candidates[1].accepted(productId: 'p9', quantity: 3);

      final ShelfRead after = parsed.withCandidate(answered);

      expect(after.candidates[1].productId, 'p9');
      expect(after.candidates[1].quantity, 3);
      expect(after.candidates[1].resolution, LineResolution.matched);
      // The region the user did not touch keeps everything, including its own box.
      expect(after.candidates[0].productId, 'p1');
      expect(after.candidates[0].left, 0.1);
    });

    test('rejecting drops the product it pointed at', () {
      final ShelfRead after = parsed.withCandidate(parsed.candidates[0].rejected);

      // The server's CHECK requires a rejected row to point at nothing, so sending an id with a
      // rejection would be a 500 rather than a refusal.
      expect(after.candidates[0].resolution, LineResolution.rejected);
      expect(after.candidates[0].productId, isNull);
      expect(after.settled, isEmpty);
    });
  });

  group('ShelfController', () {
    test('the upload and the read are two requests, in that order', () async {
      final List<String> urls = <String>[];

      Http.fake((MagicRequest request) {
        urls.add(request.url);

        return MagicResponse(
          statusCode: request.url.endsWith('/shelf-reads') ? 201 : 200,
          data: <String, dynamic>{'data': read([candidate(const <String, dynamic>{})])},
        );
      });

      final ShelfController controller = ShelfController()..begin(photo());
      await controller.uploadAndRead();

      // Two requests rather than one, because the row has to exist before a model is asked
      // anything: that is what keeps the photograph on screen immediately and a failed read
      // resumable.
      expect(urls, <String>['/shelf-reads', '/shelf-reads/s1/read']);
      expect(controller.read!.candidates, hasLength(1));
      expect(controller.reading, isFalse);
    });

    test('a failed upload never asks for a read', () async {
      final List<String> urls = <String>[];

      Http.fake((MagicRequest request) {
        urls.add(request.url);

        return MagicResponse(
          statusCode: 422,
          data: const <String, dynamic>{'message': 'This picture holds too many pixels to process.'},
        );
      });

      final ShelfController controller = ShelfController()..begin(photo());
      await controller.uploadAndRead();

      expect(urls, <String>['/shelf-reads']);
      // The server's own sentence, from the response BODY: `MagicResponse.message` carries the HTTP
      // status line instead, which is how "too many pixels" became "Unprocessable Content" on the
      // product-photo path before its test caught it.
      expect(controller.error, 'This picture holds too many pixels to process.');
    });

    test('no credit is a read the user can still review, not an error', () async {
      Http.fake((MagicRequest request) => MagicResponse(
        statusCode: request.url.endsWith('/shelf-reads') ? 201 : 200,
        data: <String, dynamic>{
          'data': read(const <Map<String, dynamic>>[], outcome: 'no_credit'),
        },
      ));

      final ShelfController controller = ShelfController()..begin(photo());
      await controller.uploadAndRead();

      expect(controller.error, isNull);
      expect(controller.read!.lastReadOutcome, 'no_credit');
      expect(controller.read!.candidates, isEmpty);
    });

    test('a re-read of a committed shelf is answered rather than treated as a failure', () async {
      Http.fake((MagicRequest request) {
        if (request.url.endsWith('/shelf-reads')) {
          return MagicResponse(
            statusCode: 201,
            data: <String, dynamic>{'data': read([candidate(const <String, dynamic>{})])},
          );
        }

        return MagicResponse(
          statusCode: 409,
          data: <String, dynamic>{
            'data': <String, dynamic>{
              ...read([candidate(const <String, dynamic>{})]),
              'confirmed_at': '2026-09-01T11:00:00+00:00',
            },
          },
        );
      });

      final ShelfController controller = ShelfController()..begin(photo());
      await controller.uploadAndRead();
      await controller.reread();

      // 409 carries the read as it stands, because the movements point at the candidates a re-read
      // would delete. The screen catches up instead of arguing.
      expect(controller.error, isNull);
      expect(controller.read!.isConfirmed, isTrue);
    });

    test('the commit sends the settled regions and the rejected ones, keyed by region', () async {
      Object? body;

      Http.fake((MagicRequest request) {
        if (request.url.contains('commit')) body = request.data;

        return MagicResponse(
          statusCode: request.url.endsWith('/shelf-reads') ? 201 : 200,
          data: <String, dynamic>{
            'data': read([
              candidate(const <String, dynamic>{'region': 1}),
              candidate(const <String, dynamic>{'region': 2, 'resolution': 'unresolved', 'product_id': null, 'quantity': null}),
              candidate(const <String, dynamic>{'region': 3}),
            ]),
          },
        );
      });

      final ShelfController controller = ShelfController()..begin(photo());
      await controller.uploadAndRead();

      controller.decide(controller.read!.candidates[2].rejected);

      expect(await controller.commit(locationId: 'loc-1'), isNull);

      final Map<String, dynamic> sent = Map<String, dynamic>.from(body! as Map);
      expect(sent['location_id'], 'loc-1');
      // Keyed by REGION, because that is what the screen shows and what the user points at (D60).
      expect((sent['accepted'] as Map).keys, <String>['1']);
      expect(sent['rejected'], <int>[3]);
      // Region 2 is unresolved and untouched, so it is in neither list: the server leaves it exactly
      // as it was, which is what makes an interrupted review resumable rather than a restart.
    });

    test('a committed shelf is not offered for review again after reset', () async {
      Http.fake((MagicRequest request) => MagicResponse(
        statusCode: request.url.endsWith('/shelf-reads') ? 201 : 200,
        data: <String, dynamic>{'data': read([candidate(const <String, dynamic>{})])},
      ));

      final ShelfController controller = ShelfController()..begin(photo());
      await controller.uploadAndRead();

      expect(controller.read, isNotNull);

      controller.reset();

      // **`reset()` used to clear the photograph and leave the read published.** The controller is a
      // type-keyed singleton and `/shelf-photo` is a named route, so a back navigation re-entered the
      // screen, drew the boxes of an already-written shelf over a placeholder, and answered a second
      // submit with "N products written to stock" while the server wrote nothing.
      expect(controller.read, isNull);
      expect(controller.photo, isNull);
    });

    test('an already-written region is not counted on the accept button', () {
      final ShelfRead parsed = ShelfRead.fromApi(read([
        candidate(const <String, dynamic>{'region': 1}),
        candidate(const <String, dynamic>{
          'region': 2,
          'confirmed_at': '2026-09-01T11:00:00+00:00',
        }),
      ]));

      // The server skips an answered candidate and answers 200, so a screen that could not see
      // `confirmed_at` counted a written region again and reported it as written a second time.
      expect(parsed.candidates[1].isAnswered, isTrue);
      expect(parsed.settled.map((ShelfCandidate c) => c.region), <int>[1]);
    });

    test('the commit omits a region already written and carries an idempotency key', () async {
      Object? body;

      Http.fake((MagicRequest request) {
        if (request.url.contains('commit')) body = request.data;

        return MagicResponse(
          statusCode: request.url.endsWith('/shelf-reads') ? 201 : 200,
          data: <String, dynamic>{
            'data': read([
              candidate(const <String, dynamic>{'region': 1}),
              candidate(const <String, dynamic>{
                'region': 2,
                'confirmed_at': '2026-09-01T11:00:00+00:00',
              }),
            ]),
          },
        );
      });

      final ShelfController controller = ShelfController()..begin(photo());
      await controller.uploadAndRead();

      expect(await controller.commit(locationId: 'loc-1'), isNull);

      final Map<String, dynamic> sent = Map<String, dynamic>.from(body! as Map);

      expect((sent['accepted'] as Map).keys, <String>['1']);
      // `IdempotencyKey::forRow(null, ...)` returns null, which switches the `stock_movements` unique
      // index off: without a key the only guard is the `confirmed_at` the committer reads outside its
      // own transaction.
      expect(sent['idempotency_key'], 'shelf-s1');
    });

    test('no credit is reported as itself rather than as an unreadable photo', () async {
      Http.fake((MagicRequest request) => MagicResponse(
        statusCode: request.url.endsWith('/shelf-reads') ? 201 : 200,
        data: <String, dynamic>{
          'data': read(const <Map<String, dynamic>>[], outcome: 'no_credit'),
        },
      ));

      final ShelfController controller = ShelfController()..begin(photo());
      await controller.uploadAndRead();

      // The screen branches on this, which the model's docblock claimed all along while nothing did.
      expect(controller.read!.lastReadOutcome, 'no_credit');
      expect(controller.error, isNull);
    });

    test('a failed upload leaves no read for the screen to offer a re-read of', () async {
      Http.fake((MagicRequest request) => MagicResponse(
        statusCode: 422,
        data: const <String, dynamic>{'message': 'This picture holds too many pixels to process.'},
      ));

      final ShelfController controller = ShelfController()..begin(photo());
      await controller.uploadAndRead();

      // This pair is what the screen has to tell apart: an error with NO read is an upload refusal,
      // and offering "try again" there called `reread()`, which returns on its first line.
      expect(controller.read, isNull);
      expect(controller.error, isNotNull);

      // Proven rather than asserted about the view: the re-read really is a no-op here, so a button
      // wired to it really did nothing.
      await controller.reread();

      expect(controller.read, isNull);
    });

    test('a second capture does not let the first read land on it', () async {
      int calls = 0;

      Http.fake((MagicRequest request) {
        calls++;

        return MagicResponse(
          statusCode: request.url.endsWith('/shelf-reads') ? 201 : 200,
          data: <String, dynamic>{
            'data': read([candidate(<String, dynamic>{'product_name': 'Capture $calls'})]),
          },
        );
      });

      final ShelfController controller = ShelfController()..begin(photo());
      final Future<void> first = controller.uploadAndRead();

      // A second capture while the first is in flight: backing out and shooting again is ordinary,
      // and without the generation counter the first answer draws boxes over the second photograph.
      controller.begin(photo());

      await first;

      expect(controller.read, isNull, reason: 'the stale answer must not publish');
    });
  });
}
