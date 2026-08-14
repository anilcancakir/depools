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
  final Map<String, (String, Duration, String?)> answers = <String, (String, Duration, String?)>{};

  /// The brand the cascade knows for a code, when it knows one.
  final Map<String, String> brands = <String, String>{};

  /// The unit a source suggests for a code. In practice only stage 1 sends one.
  final Map<String, String> unitHints = <String, String>{};

  /// Every POST body this wire was handed, so a test can assert what was SENT rather than only what
  /// came back. The batch's shape is the contract with the endpoint, and it is the half a green
  /// response cannot check.
  final List<(String, dynamic)> posts = <(String, dynamic)>[];

  /// What the next POST answers with. Defaults to a 201, which is what the batch endpoint returns.
  MagicResponse postResponse = MagicResponse(
    statusCode: 201,
    data: <String, dynamic>{'data': <String, dynamic>{'lines': <dynamic>[]}},
  );

  /// Codes whose lookup throws rather than answering.
  ///
  /// A failed RESPONSE already resolves to an unmatched row, so it cannot exercise the path where the
  /// wire itself gives out: a socket dropped mid-request, which at a receiving bench on shop wifi is
  /// not exotic. Without this the row left holding the place for that answer would stay there forever.
  final Set<String> throwOn = <String>{};

  /// The location the last delivery went to, or null for a tenant with no history.
  String? lastLocation;

  /// Any earlier destinations behind it, for the picker's recent section.
  List<String> otherRecents = const <String>[];

  /// How long a POST takes, so a test can act on the batch WHILE the write is out.
  Duration postDelay = Duration.zero;

  @override
  Future<MagicResponse> post(
    String url, {
    dynamic data,
    Map<String, String>? headers,
  }) async {
    posts.add((url, data));

    await Future<void>.delayed(postDelay);

    return postResponse;
  }

  @override
  Future<MagicResponse> get(
    String url, {
    Map<String, dynamic>? query,
    Map<String, String>? headers,
  }) async {
    if (url.contains('recent-receiving-locations')) {
      return MagicResponse(
        statusCode: 200,
        data: <String, dynamic>{
          'data': <String, dynamic>{
            // The FIRST is the default the batch opens with; the rest are the picker's top rows.
            'location_ids': <String>[?lastLocation, ...otherRecents],
          },
        },
      );
    }

    for (final String code in throwOn) {
      if (url.contains('code=$code')) {
        throw StateError('the wire gave out');
      }
    }

    for (final MapEntry<String, (String, Duration, String?)> entry in answers.entries) {
      if (!url.contains('code=${entry.key}')) continue;

      await Future<void>.delayed(entry.value.$2);

      return MagicResponse(
        statusCode: 200,
        data: <String, dynamic>{
          'data': <String, dynamic>{
            'name': entry.value.$1,
            // A null product id is the CATALOGUE shape: the cascade said what the thing is and this
            // tenant has never held one. A non-null id is stage 1, their own product.
            'source': entry.value.$3 == null ? 'community' : 'own',
            'product_id': entry.value.$3,
            'brand': brands[entry.key],
            'unit_hint': unitHints[entry.key],
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
/// The sentinel that separates "no product id was passed" from "null was passed on purpose".
const String _own = '__own__';

void main() {
  late _SlowWire wire;

  /// `productId` defaults to `p-<code>`, which is the stage-1 shape: the tenant owns it. Passing
  /// null is the catalogue shape, where the cascade said what the thing is and the tenant has never
  /// held one.
  void answers(
    String code,
    String name, {
    Duration delay = Duration.zero,
    String? productId = _own,
  }) {
    wire.answers[code] = (name, delay, productId == _own ? 'p-$code' : productId);
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

  // `flutter test` gives each FILE its own isolate, so this cannot currently leak into another one.
  // Kept anyway: it costs a line, and the day two files share a process the absence of it would be
  // a failure nobody could place.
  tearDown(Magic.flush);

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

  test('a repeat during a lookup takes the row to the front', () async {
    // The invariant the banking fix broke on its way in: a banked repeat kept the FIRST scan's
    // sequence, so the row could sit below a code scanned between the two reads. Three scans, and
    // the repeat is LAST, so the row it lands on has to lead.
    answers('slow', 'Slow Product', delay: const Duration(milliseconds: 140));
    answers('quick', 'Quick Product');

    final ScanController controller = ScanController.instance;

    final Future<void> first = controller.scan('slow');
    await controller.scan('quick');
    final Future<void> repeat = controller.scan('slow');

    await Future.wait<void>(<Future<void>>[first, repeat]);

    expect(
      controller.entries.map((ScanEntry e) => e.productName).toList(),
      <String>['Slow Product', 'Quick Product'],
      reason: 'the repeat was the last read, so its row leads',
    );
    expect(controller.entries.first.count, 2);
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

  group('committing the batch', () {
    test('an unmatched row is left behind rather than sent', () async {
      // It has no product and no usable name, so there is nothing to create. The count above the
      // button already says how many are waiting, and the batch survives the commit so the user can
      // finish them.
      answers('869', 'Whole Milk 1 L');

      final ScanController controller = ScanController.instance;
      wire.lastLocation = 'loc-1';
      await controller.loadDestination();

      await controller.scan('869');
      await controller.scan('nothing-knows-this');

      expect(await controller.commit(), isNull);

      final (String url, dynamic body) = wire.posts.single;
      expect(url, contains('receive-batch'));
      expect((body['lines'] as List<dynamic>), hasLength(1));
      // The row that was written is gone; the one still needing the user is not.
      expect(controller.entries, hasLength(1));
      expect(controller.unmatchedCount, 1);
    });

    test('a row the tenant owns is sent as an id, not as a card', () async {
      // Sending a name for a product that already exists would create a second one beside it.
      wire.lastLocation = 'loc-1';
      answers('869', 'Whole Milk 1 L');

      final ScanController controller = ScanController.instance;
      await controller.loadDestination();
      await controller.scan('869');
      await controller.commit();

      final Map<String, dynamic> line =
          (wire.posts.single.$2['lines'] as List<dynamic>).single as Map<String, dynamic>;

      expect(line['product_id'], 'p-869');
      expect(line.containsKey('name'), isFalse);
    });

    test('a catalogue row is sent as the card to create, with its barcode', () async {
      // The cascade said what the thing IS and this tenant has never held one, so the line carries
      // what the endpoint needs to create it. Without the barcode the next scan of the same carton
      // misses and creates a second product.
      wire.lastLocation = 'loc-1';
      answers('869', 'Community Milk', productId: null);

      final ScanController controller = ScanController.instance;
      await controller.loadDestination();
      await controller.scan('869');
      await controller.commit();

      final Map<String, dynamic> line =
          (wire.posts.single.$2['lines'] as List<dynamic>).single as Map<String, dynamic>;

      expect(line['name'], 'Community Milk');
      expect(line['barcode'], '869');
      expect(line.containsKey('product_id'), isFalse);
    });

    test('the count travels as the quantity', () async {
      // Two reads of one carton are two units, which is the whole prior this screen was built on.
      wire.lastLocation = 'loc-1';
      answers('869', 'Whole Milk 1 L');

      final ScanController controller = ScanController.instance;
      await controller.loadDestination();
      await controller.scan('869');
      await controller.scan('869');
      await controller.commit();

      final Map<String, dynamic> line =
          (wire.posts.single.$2['lines'] as List<dynamic>).single as Map<String, dynamic>;

      expect(line['quantity'], 2);
    });

    test('nothing is sent without a destination', () async {
      // A tenant on their first delivery has no last-received shelf, so the screen has to ask rather
      // than guess: writing stock to an arbitrary location is a compensating movement to undo.
      wire.lastLocation = null;
      answers('869', 'Whole Milk 1 L');

      final ScanController controller = ScanController.instance;
      await controller.loadDestination();
      await controller.scan('869');

      expect(await controller.commit(), isNotNull, reason: 'it returns a sentence to show');
      expect(wire.posts, isEmpty);
      // And the batch is untouched, so nothing of the user's work is lost to the refusal.
      expect(controller.entries, hasLength(1));
    });

    test('a refused write keeps the batch and the server sentence', () async {
      // The rows are still on the shelf in front of the user. Clearing them because the server said
      // no would throw away the scanning and leave the stock unrecorded.
      wire.lastLocation = 'loc-1';
      answers('869', 'Whole Milk 1 L');
      wire.postResponse = MagicResponse(
        statusCode: 422,
        data: <String, dynamic>{'message': 'This barcode already belongs to Süt.'},
      );

      final ScanController controller = ScanController.instance;
      await controller.loadDestination();
      await controller.scan('869');

      expect(await controller.commit(), 'This barcode already belongs to Süt.');
      expect(controller.entries, hasLength(1));
    });

    test('a second press while the first is in flight sends nothing', () async {
      // The ledger is append-only, so a double press appends the whole batch twice and the fix is a
      // compensating movement per row.
      wire.lastLocation = 'loc-1';
      answers('869', 'Whole Milk 1 L', delay: const Duration(milliseconds: 100));

      final ScanController controller = ScanController.instance;
      await controller.loadDestination();
      await controller.scan('869');

      await Future.wait<String?>(<Future<String?>>[controller.commit(), controller.commit()]);

      expect(wire.posts, hasLength(1));
    });

    test('a chosen destination is what the batch is sent to', () async {
      wire.lastLocation = 'loc-1';
      answers('869', 'Whole Milk 1 L');

      final ScanController controller = ScanController.instance;
      await controller.loadDestination();
      controller.chooseDestination('loc-2');
      await controller.scan('869');
      await controller.commit();

      expect(wire.posts.single.$2['location_id'], 'loc-2');
    });
  });

  group('filling in a barcode nothing knew', () {
    test('a filled row becomes writable and commits as a card', () async {
      // The whole point of the draft sheet: a code nobody could answer becomes a product, and the
      // person holding the carton is the one who named it.
      wire.lastLocation = 'loc-1';

      final ScanController controller = ScanController.instance;
      await controller.loadDestination();
      await controller.scan('nobody-knows-this');

      expect(controller.entries.single.isSettled, isFalse, reason: 'nothing answered it');

      controller.fill(
        'nobody-knows-this',
        name: 'Yeni Ürün',
        unit: 'kg',
        brand: 'Bir Marka',
      );

      final ScanEntry row = controller.entries.single;
      expect(row.isSettled, isTrue, reason: 'a named row can be written');
      expect(row.productName, 'Yeni Ürün');
      // Their own answer, so the row prints no provenance: `ScanSource` says how far to trust an
      // answer, and the person holding the carton is the most authoritative source there is.
      expect(row.source, ScanSource.own);
      // And null, so the commit sends the card to create rather than an id that does not exist.
      expect(row.productId, isNull);

      await controller.commit();

      final Map<String, dynamic> line =
          (wire.posts.single.$2['lines'] as List<dynamic>).single as Map<String, dynamic>;

      expect(line['name'], 'Yeni Ürün');
      expect(line['base_unit'], 'kg');
      expect(line['brand'], 'Bir Marka');
      expect(line['barcode'], 'nobody-knows-this');
      expect(line.containsKey('product_id'), isFalse);
    });

    test('the count a row already had survives being filled', () async {
      // Two boxes of the same unknown thing scanned before the sheet was answered. Resetting to one
      // would silently lose a carton, and the user has no way to notice.
      wire.lastLocation = 'loc-1';

      final ScanController controller = ScanController.instance;
      await controller.loadDestination();
      await controller.scan('unknown');
      await controller.scan('unknown');

      controller.fill('unknown', name: 'İki Kutu', unit: 'adet');

      expect(controller.entries.single.count, 2);
    });

    test('unticking the box on a draft travels to the endpoint', () async {
      // D117 is a default, not a rule: a private recipe or an own-brand SKU is exactly the case the
      // switch exists for, and it has to reach the server to mean anything.
      wire.lastLocation = 'loc-1';

      final ScanController controller = ScanController.instance;
      await controller.loadDestination();
      await controller.scan('unknown');
      controller.fill('unknown', name: 'Gizli', unit: 'adet', contribute: false);
      await controller.commit();

      final Map<String, dynamic> line =
          (wire.posts.single.$2['lines'] as List<dynamic>).single as Map<String, dynamic>;

      expect(line['contribute'], isFalse);
    });

    test('filling a row that is no longer in the batch changes nothing', () async {
      // The sheet can outlive its row: a commit or a removal while it is open leaves nothing to
      // update, and writing the draft into a fresh batch would attach it to a carton nobody scanned.
      wire.lastLocation = 'loc-1';

      final ScanController controller = ScanController.instance;
      await controller.loadDestination();
      await controller.scan('unknown');
      controller.clear();

      controller.fill('unknown', name: 'Hayalet', unit: 'adet');

      expect(controller.entries, isEmpty);
    });

    test('a filled row keeps the product id it arrived with', () async {
      // **This test caught a defect by contradicting its own name.** The first version asserted the
      // id was dropped, and dropping it means the commit sends a card to create for a barcode already
      // linked to the tenant's product: the server refuses that by design, so editing an owned row
      // was a guaranteed 422. The id is carried, and the sheet does not offer to rename an owned
      // product at all.
      wire.lastLocation = 'loc-1';
      answers('869', 'Milk');

      final ScanController controller = ScanController.instance;
      await controller.loadDestination();
      await controller.scan('869');

      expect(controller.entries.single.productId, 'p-869');

      controller.fill('869', name: 'Süt', unit: 'adet');

      expect(controller.entries.single.productName, 'Süt');
      expect(controller.entries.single.productId, 'p-869');

      await controller.commit();

      final Map<String, dynamic> line =
          (wire.posts.single.$2['lines'] as List<dynamic>).single as Map<String, dynamic>;

      // An id, so the stock lands on the product they already have rather than trying to make a
      // second one.
      expect(line['product_id'], 'p-869');
      expect(line.containsKey('name'), isFalse);
    });
  });

  group('the batch keeps moving while the write is out', () {
    test('a row whose lookup lands during the write is not swept with the written ones', () async {
      // The review finding, and the loss is silent: the sweep removed whatever was settled when the
      // response came back rather than what was actually posted, so a row still being looked up when
      // the button was pressed was deleted without ever having been written. Reachable at a bench:
      // scan five things, the fifth is new so it goes to Open Food Facts, press Add straight away.
      wire.lastLocation = 'loc-1';
      wire.postDelay = const Duration(milliseconds: 120);
      answers('written', 'Already Known');
      answers('late', 'Answered Late', delay: const Duration(milliseconds: 60));

      final ScanController controller = ScanController.instance;
      await controller.loadDestination();
      await controller.scan('written');

      // Started but NOT awaited, so it is still in flight when the commit goes out.
      final Future<void> late = controller.scan('late');
      final Future<String?> commit = controller.commit();

      await Future.wait<void>(<Future<void>>[late, commit]);

      expect(
        controller.entries.map((ScanEntry e) => e.barcode).toList(),
        <String>['late'],
        reason: 'the row that was never posted survives, the posted one leaves',
      );
      expect(
        (wire.posts.single.$2['lines'] as List<dynamic>),
        hasLength(1),
        reason: 'and it really was not in the request',
      );
    });

    test('a repeat read during the write keeps the count that was not written', () async {
      // The narrower half. The row was posted as N and is N+1 by the time the response lands, so
      // deleting it by key would drop the carton that arrived too late for this batch.
      wire.lastLocation = 'loc-1';
      wire.postDelay = const Duration(milliseconds: 120);
      answers('869', 'Whole Milk 1 L');

      final ScanController controller = ScanController.instance;
      await controller.loadDestination();
      await controller.scan('869');
      await controller.scan('869');

      final Future<String?> commit = controller.commit();
      await controller.scan('869');
      await commit;

      final Map<String, dynamic> line =
          (wire.posts.single.$2['lines'] as List<dynamic>).single as Map<String, dynamic>;

      expect(line['quantity'], 2, reason: 'two were posted');
      expect(controller.entries, hasLength(1));
      expect(controller.entries.single.count, 1, reason: 'the third carton is still waiting');
    });
  });

  group('a lookup that has not answered yet', () {
    test('a read is in the batch before its answer is', () async {
      // The gap the pending row closes. A stage-3 read is an Open Food Facts round trip and a
      // community hit is translated synchronously on the way back, so the queue used to sit unchanged
      // for as long as that took: indistinguishable, at a bench, from a scan the app missed.
      answers('869', 'Whole Milk 1 L', delay: const Duration(milliseconds: 120));

      final ScanController controller = ScanController.instance;
      final Future<void> scan = controller.scan('869');

      expect(controller.entries, hasLength(1), reason: 'the row holds its own place');
      expect(controller.entries.single.pending, isTrue);
      expect(controller.entries.single.productName, isNull, reason: 'there is no answer yet to show');

      await scan;

      expect(controller.entries.single.pending, isFalse);
      expect(controller.entries.single.productName, 'Whole Milk 1 L');
    });

    test('a lookup still out is not a barcode that could not be matched', () async {
      // `unmatchedCount` read `!isSettled`, which is true of a pending row as well as of a failed one,
      // so the line above the commit button accused the cascade of failing a question it had not
      // finished answering.
      answers('869', 'Whole Milk 1 L', delay: const Duration(milliseconds: 120));

      final ScanController controller = ScanController.instance;
      final Future<void> scan = controller.scan('869');

      expect(controller.unmatchedCount, 0);
      expect(controller.entries.single.isSettled, isFalse, reason: 'nor is it writable yet');

      await scan;

      expect(controller.unmatchedCount, 0);
    });

    test('an answer given while the lookup is out is not overwritten by it', () async {
      // The race the `!row.pending` guard exists for. The user can open the card and type while the
      // question is still out, and the late answer would then replace what they wrote with what a
      // catalogue guessed. The person holding the carton outranks the cascade.
      answers(
        '869',
        'Catalogue Name',
        productId: null,
        delay: const Duration(milliseconds: 120),
      );

      final ScanController controller = ScanController.instance;
      final Future<void> scan = controller.scan('869');

      controller.fill('869', name: 'What The Carton Says', unit: 'piece');

      await scan;

      expect(controller.entries.single.productName, 'What The Carton Says');
      expect(controller.entries.single.pending, isFalse);
    });

    test('a lookup that throws leaves a row the user can finish', () async {
      // Only reachable when the wire itself gives out, since a failed response already resolves to an
      // unmatched row. Without the `finally`, the row stays pending forever: it cannot be committed,
      // and it cannot be opened either, because the view withholds the tap while a lookup is out.
      wire.throwOn.add('869');

      final ScanController controller = ScanController.instance;

      await expectLater(controller.scan('869'), throwsA(isA<StateError>()));

      expect(controller.entries, hasLength(1), reason: 'the batch survives a failed lookup');
      expect(controller.entries.single.pending, isFalse);
      expect(controller.entries.single.needsUser, isTrue);
    });
  });

  group('asking about a row once', () {
    test('a catalogue find asks, a product the tenant already owns does not', () async {
      // The line this screen draws, and it is drawn at the product id rather than at the stage that
      // answered: a find becomes a NEW product in this tenant's inventory, and one they already hold
      // becomes nothing but a movement.
      answers('own', 'Their Own Milk');
      answers('cat', 'Catalogue Milk', productId: null);

      final ScanController controller = ScanController.instance;

      await controller.scan('own');
      await controller.scan('cat');

      final ScanEntry own = controller.entries.firstWhere((ScanEntry e) => e.barcode == 'own');
      final ScanEntry found = controller.entries.firstWhere((ScanEntry e) => e.barcode == 'cat');

      expect(own.needsAsking, isFalse, reason: 'it is already theirs, there is nothing to confirm');
      expect(found.needsAsking, isTrue, reason: 'a name nobody here has confirmed gets one look');
    });

    test('a confirmed find does not ask again on the next carton', () async {
      // Otherwise the second box of the same thing reopens the card, which is the modal-per-read the
      // feature document rejects outright.
      answers('cat', 'Catalogue Milk', productId: null);

      final ScanController controller = ScanController.instance;

      await controller.scan('cat');
      controller.markAsked('cat');
      await controller.scan('cat');

      expect(controller.entries.single.count, 2, reason: 'two cartons still count as two');
      expect(controller.entries.single.needsAsking, isFalse);
      expect(
        controller.entries.single.productName,
        'Catalogue Milk',
        reason: 'closing the card leaves the answer alone rather than clearing it',
      );
    });

    test('the unit a tenant keeps their own product in reaches the row', () async {
      // Dropped the same way the brand was, and more visibly: the row for a product they already own
      // printed the model's default rather than the unit that product is actually kept in. The shared
      // catalogue sends no unit at all, deliberately, so this only ever comes from stage 1.
      answers('own', 'Tomatoes');
      wire.unitHints['own'] = 'kg';

      final ScanController controller = ScanController.instance;

      await controller.scan('own');

      expect(controller.entries.single.unit, 'kg');
    });

    test('a find with no unit keeps the default rather than an empty one', () async {
      answers('cat', 'Ayran 250 ml', productId: null);

      final ScanController controller = ScanController.instance;

      await controller.scan('cat');

      expect(controller.entries.single.unit, ScanEntry.defaultUnit);
    });

    test('the brand the cascade knew reaches the card', () async {
      // It was dropped on the floor between the response and the row, so a find whose brand the
      // catalogue held presented as one with no brand: the user retypes what we already had, or the
      // product is created without it. Driving the screen found this; reading the controller did not.
      answers('cat', 'Ayran 250 ml', productId: null);
      wire.brands['cat'] = 'Sütaş';

      final ScanController controller = ScanController.instance;

      await controller.scan('cat');

      expect(controller.entries.single.brand, 'Sütaş');
    });

    test('filling a row records that it was asked', () async {
      // The other way out of the card. Without this the row a user typed would be asked about again on
      // the next read, which is the same defect as the cancel path wearing different clothes.
      final ScanController controller = ScanController.instance;

      await controller.scan('unknown-code');

      expect(controller.entries.single.needsAsking, isTrue);

      controller.fill('unknown-code', name: 'Typed By Hand', unit: 'piece');

      expect(controller.entries.single.needsAsking, isFalse);
    });
  });
}
