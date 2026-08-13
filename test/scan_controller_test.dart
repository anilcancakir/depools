import 'package:depools/app/controllers/scan_controller.dart';
import 'package:depools/app/models/scan_entry.dart';
import 'package:depools/app/models/scan_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';

/// A fake wire that can be SLOW, which magic's own fake cannot be.
///
/// `FakeNetworkDriver._handle` is synchronous and `FakeRequestHandler` returns a `MagicResponse`
/// rather than a future, so a stub cannot delay. That matters here more than anywhere: the ordering
/// defect this file pins only exists because a local hit answers in milliseconds and a stage-3
/// lookup in half a second, and a fake that answers instantly cannot express the difference. My
/// first attempt passed an `async` callback, which Dart accepted through the `dynamic` parameter and
/// then silently ignored, so the test could not fail.
class _SlowWire extends FakeNetworkDriver {
  /// Code to the name it resolves to and how long the wire takes.
  final Map<String, (String, Duration)> answers = <String, (String, Duration)>{};

  @override
  Future<MagicResponse> get(
    String url, {
    Map<String, dynamic>? query,
    Map<String, String>? headers,
  }) async {
    for (final MapEntry<String, (String, Duration)> entry in answers.entries) {
      if (!url.contains('code=${entry.key}')) continue;

      await Future<void>.delayed(entry.value.$2);

      return MagicResponse(
        statusCode: 200,
        data: <String, dynamic>{
          'data': <String, dynamic>{
            'name': entry.value.$1,
            'source': 'own',
            'product_id': null,
          },
        },
      );
    }

    // Nothing answers: stage 6, which is an ordinary outcome rather than an error.
    return MagicResponse(statusCode: 404, data: const <String, dynamic>{});
  }
}

/// The batch a scanning session accumulates.
///
/// **The controller under test is the real one, calling through the real `Http` facade.** Only the
/// wire is swapped, by binding a driver into the container under `network`, which is what the facade
/// resolves. Three of these pin review findings and none of them can be seen without controlling
/// latency.
void main() {
  late _SlowWire wire;

  void answers(String code, String name, {Duration delay = Duration.zero}) {
    wire.answers[code] = (name, delay);
  }

  setUp(() {
    // **`flush()` and not just a re-registration.** Re-binding `network` left the container's
    // ALREADY-RESOLVED singleton in place, so the previous test's wire went on answering and a code
    // with no stub returned the previous test's product. The container-shaped version of a fixture
    // leaking between tests.
    Magic.flush();

    wire = _SlowWire();
    Magic.singleton('network', () => wire);
  });

  test('a resolved scan lands in the batch with what the cascade said', () {
    answers('869', 'Whole Milk 1 L');

    return ScanController.instance.scan('869').then((_) {
      final List<ScanEntry> batch = ScanController.instance.entries;

      expect(batch, hasLength(1));
      expect(batch.first.productName, 'Whole Milk 1 L');
      expect(batch.first.source, ScanSource.own);
      expect(batch.first.count, 1);
    });
  });

  test('a code nothing answers for is an unmatched row, not an error', () {
    // Stage 6 is an ordinary outcome: a 404 is what sends the user to type the card, and blanking
    // the batch over it would throw away work they did with their hands. No `answers()` call, so
    // the wire returns 404 by construction.
    return ScanController.instance.scan('869').then((_) {
      expect(ScanController.instance.entries.single.source, ScanSource.unmatched);
      expect(ScanController.instance.unmatchedCount, 1);
    });
  });

  test('the queue is ordered by when a code was SCANNED, not when its lookup returned', () async {
    // The review finding, and it needs latency to be visible at all. A stage-3 lookup takes half a
    // second and a local hit five milliseconds, so inserting on arrival puts the OLDER scan above
    // the newer one: the user scans a carton and watches a row jump to the top for a carton two
    // before it.
    // **The FAST code is scanned first and the slow one second**, which is the only arrangement
    // that discriminates. The first version had it the other way round: arrival order then happened
    // to equal newest-first, so removing the sort left the test green. Mutation testing is what
    // caught that, not reading it.
    answers('fast', 'Fast Product');
    answers('slow', 'Slow Product', delay: const Duration(milliseconds: 120));

    final ScanController controller = ScanController.instance;

    await Future.wait<void>(<Future<void>>[
      controller.scan('fast'),
      controller.scan('slow'),
    ]);

    expect(
      controller.entries.map((ScanEntry e) => e.productName).toList(),
      <String>['Slow Product', 'Fast Product'],
      reason: 'the later scan leads, even though its answer arrived last',
    );
  });

  test('a repeat during a lookup increments the row rather than starting a second one', () async {
    // The other review finding. The row does not exist during its own lookup, so a second read
    // found nothing to increment and enqueued a duplicate: two rows for one product, and a second
    // request for an answer already on its way.
    answers('869', 'Whole Milk 1 L');

    final ScanController controller = ScanController.instance;

    await Future.wait<void>(<Future<void>>[
      controller.scan('869'),
      controller.scan('869'),
    ]);

    expect(controller.entries, hasLength(1), reason: 'one product, one row');
    expect(controller.entries.single.count, 2, reason: 'two cartons, two units');
  });

  test('a repeat after the lookup increments too', () async {
    // The plain case, which is the one Anılcan asked for: scanning the same carton twice records
    // two, and it must keep working now that the in-flight path exists beside it.
    answers('869', 'Whole Milk 1 L');

    final ScanController controller = ScanController.instance;

    await controller.scan('869');
    await controller.scan('869');

    expect(controller.entries, hasLength(1));
    expect(controller.entries.single.count, 2);
    expect(controller.totalUnits, 2);
  });

  test('the same digits under two symbologies are two different labels', () {
    // The server treats the symbology as part of a non-GTIN label's identity, so the batch has to
    // as well, or one row would collect two different labels.
    answers('SHELF-1', 'A');

    final ScanController controller = ScanController.instance;

    return controller
        .scan('SHELF-1', symbology: 'code128')
        .then((_) => controller.scan('SHELF-1', symbology: 'qrcode'))
        .then((_) => expect(controller.entries, hasLength(2)));
  });

  test('clearing the batch drops a lookup that was still in flight', () async {
    // **A resolve in flight when the batch is cleared, which is the only version of this that can
    // fail.** The first attempt cleared AFTER awaiting, so nothing was in flight and the test stayed
    // green with the guard removed. The user emptying the queue is saying the batch is done; an
    // answer landing half a second later must not drop a row into the fresh one.
    answers('869', 'Whole Milk 1 L', delay: const Duration(milliseconds: 120));

    final ScanController controller = ScanController.instance;

    final Future<void> inFlight = controller.scan('869');
    controller.clear();
    await inFlight;

    expect(controller.entries, isEmpty, reason: 'the answer belonged to a batch that is gone');
    expect(controller.hasScans, isFalse);
  });

  test('a fresh batch after a clear starts its counts at one', () async {
    answers('869', 'Whole Milk 1 L');

    final ScanController controller = ScanController.instance;

    await controller.scan('869');
    controller.clear();
    await controller.scan('869');

    expect(controller.entries.single.count, 1);
  });
}
