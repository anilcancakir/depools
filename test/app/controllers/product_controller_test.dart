import 'package:depools/app/controllers/product_controller.dart';
import 'package:depools/app/models/product_filter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';

/// The controller's own state machine, which nothing could reach until now.
///
/// **This app had no controller test at all, and both defects these cases pin came out of the same
/// place: a flag set before an `await` and not cleared on every path back.** A green analyzer and a
/// green widget suite say nothing about either, because neither is a compile error and neither
/// throws; the list simply stops growing, and the screen looks like a list that ended.
///
/// `Http.fake` swaps the driver in magic's container for one that answers from a callback and
/// records what it was asked, which is the same shape as Laravel's `Http::fake()`. It needs no
/// server and no `Magic.init`, so a controller can be constructed directly rather than resolved
/// through `Magic.findOrPut`: the shared instance is what the SCREENS need, not what a test does.
void main() {
  /// One page of the products endpoint.
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
              'locations': <Map<String, dynamic>>[],
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

  group('paging', () {
    test('a filter change during a page fetch does not kill pagination', () async {
      // **The bug this exists for.** `loadMore` set its in-flight flag, awaited, and then returned
      // early when it saw a newer request id, leaving the flag set. Nothing else cleared it, so the
      // guard at the top of `loadMore` refused every later page: one filter change landing while a
      // page was in flight killed pagination for the rest of the session, and the footer kept its
      // spinner over a list that would never grow again.
      Http.fake((MagicRequest request) {
        if (request.url.contains('/locations')) return locations();

        return page(<String>['a', 'b'], next: 'CURSOR', total: 90);
      });

      final ProductController controller = ProductController();

      await controller.load();

      expect(controller.hasMore, isTrue);
      expect(controller.loadingMore, isFalse);

      // Started and deliberately NOT awaited, so the filter change lands while it is in flight.
      final Future<void> inFlight = controller.loadMore();

      await controller.apply(const ProductFilter(query: 'süt'));
      await inFlight;

      expect(
        controller.loadingMore,
        isFalse,
        reason: 'the abandoned page left its flag set, so no later page can ever be asked for',
      );

      // And the proof that it is not merely a flag: another page can still be fetched.
      await controller.loadMore();

      expect(controller.items.length, greaterThan(2));
    });

    test('a stale page is dropped rather than appended', () async {
      // Two filters' worth of rows in one list is worse than a short list: the chips would say one
      // thing and the rows would be a mixture, with nothing marking which was which.
      Http.fake((MagicRequest request) {
        if (request.url.contains('/locations')) return locations();
        if (request.url.contains('cursor=')) return page(<String>['stale'], total: 90);

        return page(<String>['fresh'], next: 'CURSOR', total: 90);
      });

      final ProductController controller = ProductController();

      await controller.load();

      final Future<void> inFlight = controller.loadMore();

      await controller.apply(const ProductFilter(query: 'süt'));
      await inFlight;

      expect(controller.items.map((i) => i.id), isNot(contains('stale')));
    });

    test('the total is the filtered set and survives a page append', () async {
      Http.fake((MagicRequest request) {
        if (request.url.contains('/locations')) return locations();
        if (request.url.contains('cursor=')) return page(<String>['c'], total: 3);

        return page(<String>['a', 'b'], next: 'CURSOR', total: 3);
      });

      final ProductController controller = ProductController();

      await controller.load();

      expect(controller.total, 3);
      expect(controller.catalogueTotal, 3, reason: 'the first load is unfiltered');

      await controller.loadMore();

      expect(controller.items.length, 3);
      expect(controller.hasMore, isFalse);
      expect(controller.total, 3);
    });

    test('a filtered first load still learns the catalogue size', () async {
      // **A shared link mounts this screen with a filter already on**, so the first load is filtered
      // and the unfiltered total is never free. It used to be written only on an empty filter, so
      // the subtitle read "11 of 0 products" and the no-matches panel would have told a tenant with
      // a hundred products that they owned none.
      Http.fake((MagicRequest request) {
        if (request.url.contains('/locations')) return locations();
        if (request.url.contains('stock_state=')) return page(<String>['a'], total: 11);

        return page(<String>['a'], total: 101);
      });

      final ProductController controller = ProductController();

      await controller.apply(const ProductFilter(stockState: StockStateFilter.outOfStock));

      expect(controller.total, 11);
      expect(controller.catalogueTotal, 101, reason: 'the unfiltered count has to be fetched here');
    });

    test('the filter travels as query parameters rather than being applied here', () async {
      final List<String> asked = <String>[];

      Http.fake((MagicRequest request) {
        asked.add(request.url);

        if (request.url.contains('/locations')) return locations();

        return page(<String>['a'], total: 1);
      });

      final ProductController controller = ProductController();

      await controller.load();
      await controller.apply(
        const ProductFilter(stockState: StockStateFilter.belowPar, locationIds: <String>{'l1'}),
      );

      final String last = asked.last;

      expect(last, contains('stock_state=below_par'));
      expect(last, contains('location_ids%5B%5D=l1'));
    });
  });

  group('shelf sweep', () {
    test('a shelf walks every page rather than stopping at the first', () async {
      // The count screen's whole sheet comes from this. A single page would be short by exactly the
      // rows nobody reached, and a count is the one place a silently short list rewrites balances.
      Http.fake((MagicRequest request) {
        if (request.url.contains('/locations')) return locations();
        if (request.url.contains('cursor=')) return page(<String>['b', 'c'], total: 3);

        return page(<String>['a'], next: 'CURSOR', total: 3);
      });

      final ProductController controller = ProductController();

      await controller.loadShelf('loc-1');

      expect(controller.hasShelf('loc-1'), isTrue);
      expect(controller.shelf('loc-1').length, 3);
      expect(controller.shelfFailed('loc-1'), isFalse);
    });

    test('a shelf that never ends is a failure, not a short shelf', () async {
      // A server that keeps answering with a cursor used to leave the partial walk CACHED as if it
      // were the whole shelf, which is the exact failure the sweep exists to prevent, only larger.
      // The stop condition has to fail loudly or it is a bug generator.
      Http.fake((MagicRequest request) {
        if (request.url.contains('/locations')) return locations();

        return page(<String>['x'], next: 'ALWAYS', total: 9999);
      });

      final ProductController controller = ProductController();

      await controller.loadShelf('loc-1');

      expect(controller.shelfFailed('loc-1'), isTrue);
      expect(
        controller.hasShelf('loc-1'),
        isFalse,
        reason: 'a partial sweep must not be readable as a complete shelf',
      );
    });

    test('a failed shelf is not retried until it is forced', () async {
      int requests = 0;

      Http.fake((MagicRequest request) {
        if (request.url.contains('/locations')) return locations();

        requests++;

        return MagicResponse(statusCode: 500, data: <String, dynamic>{});
      });

      final ProductController controller = ProductController();

      await controller.loadShelf('loc-1');
      await controller.loadShelf('loc-1');
      await controller.loadShelf('loc-1');

      expect(requests, 1, reason: 'the screen asks from build, so an unrecorded failure loops');

      await controller.loadShelf('loc-1', force: true);

      expect(requests, 2);
    });

    test('a location holding nothing is known from the location payload', () async {
      // The count screen opens on the first shelf that holds something, and it can no longer work
      // that out from the product list: that list is one page now, so a full shelf whose rows sit on
      // a later page would read as empty and the default would land on the wrong shelf.
      Http.fake((MagicRequest request) {
        if (request.url.contains('/locations')) {
          return MagicResponse(
            statusCode: 200,
            data: <String, dynamic>{
              'data': <Map<String, dynamic>>[
                <String, dynamic>{'id': 'root', 'name': 'Mutfak', 'stock_count': 0},
                <String, dynamic>{'id': 'shelf', 'name': 'Buzdolabı', 'stock_count': 4},
              ],
            },
          );
        }

        return page(<String>['a'], total: 1);
      });

      final ProductController controller = ProductController();

      await controller.load();

      expect(controller.holdsStock('root'), isFalse);
      expect(controller.holdsStock('shelf'), isTrue);
    });
  });
}
