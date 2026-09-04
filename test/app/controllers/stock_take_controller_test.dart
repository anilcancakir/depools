import 'package:depools/app/controllers/stock_take_controller.dart';
import 'package:depools/app/models/product_filter.dart';
import 'package:depools/app/support/scan_outcome.dart';
import 'package:depools/resources/views/products/count_line.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';

/// The shelf a count is taken against.
///
/// **The property under test is that a paginated count sheet is still safe**, which is not obvious
/// and is the reason this screen resisted pagination for so long. A sheet built from a page used to
/// be the defect: it LOOKED complete and was short. It is safe now for a reason the sheet itself
/// cannot show, so it is asserted here: an uncounted row writes nothing, the commit sends only what
/// was typed, and [StockTakeController.total] states the shelf's real size rather than the loaded
/// count, so a user is never told they are nearly done fifty rows into a thousand.
void main() {
  MagicResponse page(List<String> ids, {String? next, int total = 0}) {
    return MagicResponse(
      statusCode: 200,
      data: <String, dynamic>{
        'data': <Map<String, dynamic>>[
          for (final String id in ids)
            <String, dynamic>{
              'id': id,
              'name': 'Ürün $id',
              'base_unit': 'adet',
              'quantity': '1.000',
              'locations': <Map<String, dynamic>>[
                <String, dynamic>{'location_id': 'shelf', 'quantity': '1.000'},
              ],
            },
        ],
        'meta': <String, dynamic>{'next_cursor': next, 'total': total},
      },
    );
  }

  MagicResponse locations() => MagicResponse(
    statusCode: 200,
    data: <String, dynamic>{'data': <Map<String, dynamic>>[]},
  );

  tearDown(Http.unfake);

  test('the shelf is scoped to one location and states its real size', () async {
    final List<String> asked = <String>[];

    Http.fake((MagicRequest request) {
      if (request.url.contains('/locations')) return locations();

      asked.add(request.url);

      return page(<String>['a', 'b'], next: 'CURSOR', total: 940);
    });

    final StockTakeController controller = StockTakeController();

    await controller.open('shelf');

    expect(asked.single, contains('location_ids%5B%5D=shelf'));
    expect(controller.rows.length, 2);

    // **The header counts against this, not against the two loaded rows.** A shelf of 940 with a
    // page of 50 would otherwise tell the user they were nearly finished after one page.
    expect(controller.total, 940);
    expect(controller.hasMore, isTrue);
  });

  test('a page appends rather than replacing, and the total does not move', () async {
    Http.fake((MagicRequest request) {
      if (request.url.contains('/locations')) return locations();

      return request.url.contains('cursor=')
          ? page(<String>['c'], total: 3)
          : page(<String>['a', 'b'], next: 'CURSOR', total: 3);
    });

    final StockTakeController controller = StockTakeController();

    await controller.open('shelf');
    await controller.loadMore();

    expect(controller.rows.map((r) => r.id), <String>['a', 'b', 'c']);
    expect(controller.total, 3);
    expect(controller.hasMore, isFalse);
  });

  test('switching shelves drops the previous one rather than caching it', () async {
    final List<String> asked = <String>[];

    Http.fake((MagicRequest request) {
      if (request.url.contains('/locations')) return locations();

      asked.add(request.url);

      return page(<String>[request.url.contains('fridge') ? 'f' : 'p'], total: 1);
    });

    final StockTakeController controller = StockTakeController();

    await controller.open('fridge');
    await controller.open('pantry');

    expect(controller.locationId, 'pantry');
    expect(controller.rows.single.id, 'p');

    // Going back refetches. A cached shelf is a stale EXPECTED figure, and a count is checked
    // against what the record says now, so caching it would have the user counting against a
    // number that moved while they were on another shelf.
    await controller.open('fridge');

    expect(asked.length, 3);
  });

  test('opening another shelf drops the previous total rather than showing it', () async {
    // **The header would otherwise lie for a moment.** With rows already on screen the first-page
    // load skips its loading state, so the new shelf rendered the OLD one's rows and the OLD one's
    // total until the response landed: `0 of 25` for a shelf holding four.
    Http.fake((MagicRequest request) {
      if (request.url.contains('/locations')) return locations();

      return request.url.contains('big')
          ? page(<String>['a'], total: 25)
          : page(<String>['b'], total: 4);
    });

    final StockTakeController controller = StockTakeController();

    await controller.open('big');

    expect(controller.total, 25);

    // Started and not awaited, so the assertion lands while the fetch is still in flight, which is
    // the only moment the stale total was visible.
    final Future<void> opening = controller.open('small');

    expect(controller.total, 0);
    expect(controller.isLoading, isTrue);

    await opening;

    expect(controller.total, 4);
  });

  test('a search narrows the shelf on the server, from the first page', () async {
    final List<String> asked = <String>[];

    Http.fake((MagicRequest request) {
      if (request.url.contains('/locations')) return locations();

      asked.add(request.url);

      return page(<String>['a'], total: 1);
    });

    final StockTakeController controller = StockTakeController();

    await controller.open('shelf');
    await controller.search('süt');

    expect(asked.last, contains('query=s%C3%BCt'));
    expect(asked.last, contains('location_ids%5B%5D=shelf'));

    // No cursor: a narrowed shelf is a different list, so continuing the old position would ask the
    // server to resume something it never produced.
    expect(asked.last, isNot(contains('cursor=')));
  });

  test('the query outlives the screen, which is why the field has to be seeded', () async {
    // The controller is keyed by type, so leaving the count screen and coming back gives a fresh
    // `State` with an empty input while this still holds the previous query. The screen seeds its
    // field from here in `didChangeDependencies`; this pins the half that makes that necessary.
    Http.fake((MagicRequest request) {
      if (request.url.contains('/locations')) return locations();

      return page(<String>['a'], total: 1);
    });

    final StockTakeController controller = StockTakeController();

    await controller.open('shelf');
    await controller.search('süt');

    expect(controller.query, 'süt');

    // Re-opening the SAME shelf is what a remount does, and it early-returns rather than refetching,
    // so the query survives. Opening a different one drops it.
    await controller.open('shelf');

    expect(controller.query, 'süt', reason: 'a remount must not silently discard the search');

    await controller.open('other');

    expect(controller.query, isEmpty, reason: 'another shelf is another list');
  });

  test('reordering refetches, because a cursor belongs to one ordering', () async {
    final List<String> asked = <String>[];

    Http.fake((MagicRequest request) {
      if (request.url.contains('/locations')) return locations();

      asked.add(request.url);

      return page(<String>['a'], next: 'CURSOR', total: 2);
    });

    final StockTakeController controller = StockTakeController();

    await controller.open('shelf');

    // The default order states nothing, so the shelf request stays as short as it can be.
    expect(asked.single, isNot(contains('sort=')));

    await controller.reorder(ProductSort.quantity);

    expect(asked.last, contains('sort=quantity'));
    expect(asked.length, 2);
  });

  test('a page that arrives after a search is dropped rather than appended', () async {
    // Two lists' worth of rows in one sheet is worse than a short sheet: the user would count
    // against expected figures belonging to products the search had already removed.
    Http.fake((MagicRequest request) {
      if (request.url.contains('/locations')) return locations();
      if (request.url.contains('cursor=')) return page(<String>['stale'], total: 2);

      return page(<String>['fresh'], next: 'CURSOR', total: 2);
    });

    final StockTakeController controller = StockTakeController();

    await controller.open('shelf');

    final Future<void> inFlight = controller.loadMore();

    await controller.search('süt');
    await inFlight;

    expect(controller.rows.map((r) => r.id), isNot(contains('stale')));
    expect(
      controller.loadingMore,
      isFalse,
      reason: 'the abandoned page left its flag set, so no later page could be asked for',
    );
  });

  test('a failed shelf is an error rather than an empty one', () async {
    Http.fake((MagicRequest request) {
      if (request.url.contains('/locations')) return locations();

      return MagicResponse(statusCode: 500, data: <String, dynamic>{});
    });

    final StockTakeController controller = StockTakeController();

    await controller.open('shelf');

    // An empty sheet and a failed fetch look identical on screen unless the state says which it is,
    // and on a count the difference decides whether the user believes the shelf is empty.
    expect(controller.failed, isTrue);
    expect(controller.rows, isEmpty);
  });

  test('a server refusal on lines is readable through hasError/getError', () async {
    Http.fake((MagicRequest request) {
      if (request.url.contains('/locations')) return locations();
      if (request.url.contains('/stock/count')) {
        return MagicResponse(
          statusCode: 422,
          data: const <String, dynamic>{
            'message': 'The given data was invalid.',
            'errors': <String, dynamic>{
              'lines': <String>['The lines field is required.'],
            },
          },
        );
      }

      return page(<String>['a'], total: 1);
    });

    final StockTakeController controller = StockTakeController();
    await controller.open('shelf');

    final CountCommit commit = await controller.commit('shelf', <String, num>{'a': 3});

    expect(commit.error, isNotNull);
    expect(controller.hasError('lines'), isTrue);
    expect(controller.getError('lines'), isNotNull);
    // handleApiError nulls rxState on the way in; the shelf has to survive that so a user mid-walk
    // through it does not lose what is already on screen.
    expect(controller.rows, isNotEmpty);
  });

  group('resolving a scan', () {
    MagicResponse product(String id, List<String> locationIds) => MagicResponse(
      statusCode: 200,
      data: <String, dynamic>{
        'data': <String, dynamic>{
          'id': id,
          'name': 'Süt',
          'base_unit': 'adet',
          'quantity': '3.000',
          'locations': <Map<String, dynamic>>[
            for (final String locationId in locationIds)
              <String, dynamic>{'location_id': locationId, 'quantity': '3.000'},
          ],
        },
      },
    );

    test('a code on this shelf comes back ready to count', () async {
      final List<String> asked = <String>[];

      Http.fake((MagicRequest request) {
        if (request.url.contains('/locations')) return locations();
        if (request.url.contains('by-barcode')) {
          asked.add(request.url);

          return product('p1', <String>['shelf']);
        }

        return page(<String>[]);
      });

      final StockTakeController controller = StockTakeController();
      await controller.open('shelf');

      final ScanOutcome? outcome = await controller.resolveScan('8690504010012');

      expect(asked.single, contains('code=8690504010012'));
      expect(outcome?.verdict, ScanVerdict.onShelf);
    });

    test('a code the tenant owns elsewhere is not counted here', () async {
      Http.fake((MagicRequest request) {
        if (request.url.contains('/locations')) return locations();
        if (request.url.contains('by-barcode')) return product('p1', <String>['pantry']);

        return page(<String>[]);
      });

      final StockTakeController controller = StockTakeController();
      await controller.open('shelf');

      expect((await controller.resolveScan('8690504010012'))?.verdict, ScanVerdict.elsewhere);
    });

    test('a 404 is an answer and anything else is a failure', () async {
      // **The distinction the whole flow rests on.** A 404 means the tenant has no product carrying
      // this code, which is what sends the user to the catalog. A network fault reported as the same
      // thing would have them create a duplicate of a product they already own.
      int status = 404;

      Http.fake((MagicRequest request) {
        if (request.url.contains('/locations')) return locations();
        if (request.url.contains('by-barcode')) {
          return MagicResponse(statusCode: status, data: <String, dynamic>{});
        }

        return page(<String>[]);
      });

      final StockTakeController controller = StockTakeController();
      await controller.open('shelf');

      expect((await controller.resolveScan('5060337502900'))?.verdict, ScanVerdict.unknown);

      status = 500;

      expect(await controller.resolveScan('5060337502900'), isNull);
    });

    test('a symbology travels only when there is one', () async {
      final List<String> asked = <String>[];

      Http.fake((MagicRequest request) {
        if (request.url.contains('/locations')) return locations();
        if (request.url.contains('by-barcode')) {
          asked.add(request.url);

          return product('p1', <String>['shelf']);
        }

        return page(<String>[]);
      });

      final StockTakeController controller = StockTakeController();
      await controller.open('shelf');

      await controller.resolveScan('SHELF-A-0042', symbology: 'code128');
      await controller.resolveScan('8690504010012');

      expect(asked.first, contains('symbology=code128'));
      expect(asked.last, isNot(contains('symbology')));
    });
  });
}
