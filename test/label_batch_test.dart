import 'package:depools/app/controllers/label_batch_controller.dart';
import 'package:depools/app/models/print_batch.dart';
import 'package:depools/ui/components/label_item_row/label_item_row.dart' show LabelCountMode;
import 'package:depools/ui/components/label_preview/label_preview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';

/// Parsing a `labels/batches` payload, and what `LabelBatchController` does with each shape.
///
/// The payloads mirror `backend/tests/Feature/PrintBatchApiTest.php`'s own assertions rather than an
/// imagined shape: a position per line, the two D45 modes, and both sticker counts.
void main() {
  tearDown(Http.unfake);

  Map<String, dynamic> line(Map<String, dynamic> overrides) => <String, dynamic>{
    'id': 'l1',
    'position': 1,
    'product_id': 'p1',
    'product_serial_id': null,
    'name': 'Pınar Süt Tam Yağlı 1 lt',
    'serial': null,
    // **The wire carries this and the first version of the resource did not send it**, so this fixture
    // was built without it and the suite recorded the gap rather than catching it.
    'code': '8690504004073',
    'count': 12,
    'mode': 'free',
    'is_printed': false,
    'print_count': 0,
    ...overrides,
  };

  Map<String, dynamic> batch(List<Map<String, dynamic>> lines, {String? printedAt}) =>
      <String, dynamic>{
        'id': 'b1',
        'name': null,
        'template': 'a4_24_up_70x37',
        'fields': <String>['name', 'code'],
        'printed_at': printedAt,
        'sticker_count': lines.fold<int>(0, (int sum, Map<String, dynamic> l) => sum + (l['count'] as int)),
        'pending_sticker_count': lines
            .where((Map<String, dynamic> l) => l['is_printed'] == false)
            .fold<int>(0, (int sum, Map<String, dynamic> l) => sum + (l['count'] as int)),
        'items': lines,
      };

  group('PrintBatch.fromApi', () {
    test('a line carries its position, which is what every write is keyed on', () {
      final PrintBatch parsed = PrintBatch.fromApi(batch([line(const <String, dynamic>{})]));

      final PrintBatchLine only = parsed.lines.single;
      expect(only.position, 1);
      expect(only.count, 12);
      expect(only.mode, LabelCountMode.free);
      expect(only.isAdjustable, isTrue);
    });

    test('a serial line is not adjustable and neither is a printed one', () {
      final PrintBatch parsed = PrintBatch.fromApi(batch([
        line(const <String, dynamic>{'position': 1, 'mode': 'per_serial', 'serial': 'MK-1', 'count': 1}),
        line(const <String, dynamic>{'position': 2, 'is_printed': true, 'print_count': 1}),
      ]));

      // D45 twice: a serial's label identifies one unit, and a printed line's count is a record of
      // paper that already went rather than a number to edit.
      expect(parsed.lines[0].isAdjustable, isFalse);
      expect(parsed.lines[1].isAdjustable, isFalse);
    });

    test('an unreadable mode falls back to the one WITHOUT a stepper', () {
      final PrintBatch parsed = PrintBatch.fromApi(batch([
        line(const <String, dynamic>{'mode': 'something-new'}),
      ]));

      // The safe default is the one that offers no control: a stepper on a unit that exists once is
      // the mistake D45 exists to prevent.
      expect(parsed.lines.single.mode, LabelCountMode.perSerial);
      expect(parsed.lines.single.isAdjustable, isFalse);
    });

    test('a batch is unfinished while any line is', () {
      final PrintBatch open = PrintBatch.fromApi(batch([
        line(const <String, dynamic>{'position': 1, 'is_printed': true, 'print_count': 1}),
        line(const <String, dynamic>{'position': 2}),
      ]));

      expect(open.isUnfinished, isTrue);
      expect(open.printed, hasLength(1));
      expect(open.pendingStickerCount, 12);
    });

    test('the codes are the ones the server named, and a null is left out', () {
      final PrintBatch parsed = PrintBatch.fromApi(batch([
        line(const <String, dynamic>{'position': 1}),
        line(const <String, dynamic>{'position': 2, 'code': null}),
        line(const <String, dynamic>{'position': 3, 'code': null, 'serial': 'MK-1', 'mode': 'per_serial'}),
      ]));

      // **This used to substitute `DPL00000000` for a null**, on the premise that null meant "the server
      // will generate one". The resource simply was not sending the field, so the fit verdict compared a
      // constant against every template's ceiling and was wrong in both directions. A code nobody named
      // is left out, because a callout naming one nobody will print is worse than no callout.
      expect(parsed.codes, <String>['8690504004073', 'MK-1']);
    });

    test('an empty batch is resumable even though nothing in it is unprinted', () {
      final PrintBatch empty = PrintBatch.fromApi(batch(const <Map<String, dynamic>>[]));

      // **Two different questions, and conflating them stranded batches.** An empty batch has no
      // unprinted lines, so it read as finished and was never resumed; the client never deletes one
      // either, so removing the last line meant a fresh batch on every visit and the abandoned ones
      // piled up at the top of a list ordered nulls-first.
      expect(empty.isUnfinished, isFalse);
      expect(empty.isResumable, isTrue);

      final PrintBatch finished = PrintBatch.fromApi(
        batch([line(const <String, dynamic>{'is_printed': true, 'print_count': 1})],
            printedAt: '2026-09-01T10:00:00+00:00'),
      );

      expect(finished.isResumable, isFalse);
    });
  });

  group('SheetTemplate.fromApi', () {
    test('millimetres arrive as whole numbers and the code ceiling comes with them', () {
      final SheetTemplate parsed = SheetTemplate.fromApi(const <String, dynamic>{
        'key': 'a4_65_up_38x21',
        'label': "A4 · 65'li · 38×21 mm",
        // PHP sends a whole decimal as an int, so both shapes have to parse.
        'page_width_mm': 210,
        'page_height_mm': 297.0,
        'columns': 5,
        'rows': 13,
        'label_width_mm': 38,
        'label_height_mm': 21,
        'max_code_length': 7,
      });

      expect(parsed.key, 'a4_65_up_38x21');
      expect(parsed.pageHeightMm, 297);
      expect(parsed.perSheet, 65);
      // The number that makes "this will not fit" a fact rather than a heuristic. The screen used to
      // derive the same verdict from `labelHeightMm < 30`, which named a field by correlation.
      expect(parsed.maxCodeLength, 7);
    });
  });

  group('LabelBatchController', () {
    test('opening resumes the batch that still owes something', () async {
      final List<String> urls = <String>[];

      Http.fake((MagicRequest request) {
        urls.add(request.url);

        return MagicResponse(
          statusCode: 200,
          data: <String, dynamic>{
            'data': <Map<String, dynamic>>[
              batch([line(const <String, dynamic>{'position': 1, 'is_printed': true, 'print_count': 1})],
                  printedAt: '2026-09-01T10:00:00+00:00'),
              batch([line(const <String, dynamic>{'position': 1})]),
            ],
          },
        );
      });

      final LabelBatchController controller = LabelBatchController();
      await controller.open();

      // A batch exists because items are added over time, so arriving here resumes rather than
      // restarts. The finished one is skipped even though it is first in the list.
      expect(urls.first, '/labels/batches');
      expect(controller.batch, isNotNull);
      expect(controller.batch!.isUnfinished, isTrue);
    });

    test('opening with no open batch creates one', () async {
      final List<String> urls = <String>[];

      Http.fake((MagicRequest request) {
        urls.add(request.url);

        if (request.method == 'GET') {
          return MagicResponse(statusCode: 200, data: const <String, dynamic>{'data': <Object>[]});
        }

        return MagicResponse(
          statusCode: 201,
          data: <String, dynamic>{'data': batch(const <Map<String, dynamic>>[])},
        );
      });

      final LabelBatchController controller = LabelBatchController();
      await controller.open(template: 'a4_8_up_105x70');

      expect(urls, containsAllInOrder(<String>['/labels/batches', '/labels/batches']));
      expect(controller.batch, isNotNull);
    });

    test('a product handed over before opening lands in the batch', () async {
      final List<String> urls = <String>[];

      Http.fake((MagicRequest request) {
        urls.add(request.url);

        if (request.method == 'GET') {
          return MagicResponse(
            statusCode: 200,
            data: <String, dynamic>{
              'data': <Map<String, dynamic>>[batch([line(const <String, dynamic>{})])],
            },
          );
        }

        return MagicResponse(
          statusCode: 200,
          data: <String, dynamic>{'data': batch([line(const <String, dynamic>{})])},
        );
      });

      final LabelBatchController controller = LabelBatchController()..addOnOpen('p9');
      await controller.open();

      // **Drains the render debounce inside the test that started it.** A successful write ends in an
      // unawaited `Future.delayed(600ms)`, and a plain `test()` does not fail on a pending timer, so
      // it fired after `tearDown(Http.unfake)`: the render then either hit the real driver or landed
      // in a later test's fake, one of which asserts an EXACT list of urls. Green by ordering.
      await Future<void>.delayed(const Duration(milliseconds: 700));

      // `/labels` takes no parameters, so the product travels through the singleton the way the shelf,
      // receipt and draft paths all do.
      expect(urls, contains('/labels/batches/b1/lines'));
      // And the debounce did fire, rather than the wait above being a wait for nothing.
      expect(urls, contains('/labels/batches/b1/preview'));
    });

    test('a failed list does not create a second batch', () async {
      final List<String> urls = <String>[];

      Http.fake((MagicRequest request) {
        urls.add(request.url);

        return MagicResponse(
          statusCode: 500,
          data: const <String, dynamic>{'message': 'Server Error'},
        );
      });

      final LabelBatchController controller = LabelBatchController();
      await controller.open();

      // **A failed list is not an empty one.** A 500, a timeout or an offline moment used to fall
      // straight through to `_create`, so the afternoon's labels went into a fresh batch while the real
      // unfinished one still owed stickers, and nothing on screen said a second batch existed.
      expect(urls, <String>['/labels/batches']);
      expect(controller.batch, isNull);
      expect(controller.error, isNotNull);

      // **The STATUS is the channel, because `setError` nulls the state.** The screen keys its whole
      // render on the batch, so on a failure it has no batch, no template, and used to sit on
      // "Loading the sheet catalogue…" for good while this sentence existed and went unread. Pinned
      // here because the failure card now reads exactly these two.
      expect(controller.isError, isTrue);
      expect(controller.rxStatus.message, isNotNull);
    });

    test('the preview is a url, because the app cannot fetch bytes', () async {
      Http.fake((MagicRequest request) {
        if (request.method == 'GET') {
          return MagicResponse(
            statusCode: 200,
            data: <String, dynamic>{
              'data': <Map<String, dynamic>>[batch([line(const <String, dynamic>{})])],
            },
          );
        }

        return MagicResponse(
          statusCode: 200,
          data: const <String, dynamic>{
            'data': <String, dynamic>{'url': 'https://x/label-previews/abc.png', 'expires_at': null},
          },
        );
      });

      final LabelBatchController controller = LabelBatchController();
      await controller.open();
      await controller.render();

      // Magic's `Http` facade has no binary response mode and `Image.network` cannot carry a bearer
      // token, so the endpoint answers with a signed url and the component loads it.
      expect(controller.previewUrl, 'https://x/label-previews/abc.png');
      expect(controller.rendering, isFalse);
    });

    test('leaving mid-render cannot bring the previous sheet back', () async {
      Http.fake((MagicRequest request) {
        if (request.method == 'GET') {
          return MagicResponse(
            statusCode: 200,
            data: <String, dynamic>{
              'data': <Map<String, dynamic>>[batch([line(const <String, dynamic>{})])],
            },
          );
        }

        return MagicResponse(
          statusCode: 200,
          data: const <String, dynamic>{
            'data': <String, dynamic>{'url': 'https://x/label-previews/stale.png'},
          },
        );
      });

      final LabelBatchController controller = LabelBatchController();
      await controller.open();

      // The render is genuinely in flight: `render()` runs as far as its POST and yields there, so
      // the `reset()` below lands before the answer does. That is what leaving the screen does, and
      // the backend render is a Chrome with a 60-second ceiling, so the window is not theoretical.
      final Future<void> pending = controller.render();
      controller.reset();
      await pending;

      // **`reset()` used to clear the url and leave the generation counter alone**, so the answer
      // wrote it straight back and the next visit opened on the previous batch's sheet, held there by
      // `gaplessPlayback` until a fresh render replaced it.
      expect(controller.previewUrl, isNull);
    });

    test('a finished batch renders nothing rather than failing', () async {
      Http.fake((MagicRequest request) {
        if (request.method == 'GET') {
          return MagicResponse(
            statusCode: 200,
            data: <String, dynamic>{
              'data': <Map<String, dynamic>>[
                batch([line(const <String, dynamic>{'is_printed': true, 'print_count': 1})]),
              ],
            },
          );
        }

        // **A render-shaped answer, so the guard's absence would show.** The first version answered
        // every request with the list payload, which `_parse` cannot read as a url: deleting the
        // `isUnfinished` check left `previewUrl` null anyway and both assertions still passed, so the
        // test could not fail for the reason it claims.
        return MagicResponse(
          statusCode: 200,
          data: const <String, dynamic>{
            'data': <String, dynamic>{'url': 'https://x/label-previews/finished.png'},
          },
        );
      });

      final LabelBatchController controller = LabelBatchController();
      // It RESUMES rather than creating, which the first version of this comment had backwards: the
      // fixture's `printed_at` is null, so `isResumable` is true even with every line printed. That
      // is also how the screen reaches this branch.
      await controller.open();
      await controller.render();

      expect(controller.previewUrl, isNull);
      expect(controller.error, isNull);
    });

    test('a refusal is read from the response body', () async {
      Http.fake((MagicRequest request) {
        if (request.method == 'GET') {
          return MagicResponse(
            statusCode: 200,
            data: <String, dynamic>{
              'data': <Map<String, dynamic>>[batch([line(const <String, dynamic>{})])],
            },
          );
        }

        return MagicResponse(
          statusCode: 422,
          data: const <String, dynamic>{'message': 'These codes are too long for a 38x21 mm label.'},
        );
      });

      final LabelBatchController controller = LabelBatchController();
      await controller.open();
      await controller.render();

      // The driver fills `MagicResponse.message` from the HTTP status line, so reading the wrong one
      // turns a useful sentence into "Unprocessable Content".
      expect(controller.error, 'These codes are too long for a 38x21 mm label.');
      expect(controller.previewUrl, isNull);
    });
  });
}
