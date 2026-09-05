import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Whether a screen that loads by a route id notices the id changing.
///
/// **Flutter matches a route's widget by TYPE, so navigating from one location to another hands the
/// same `State` a new `id` without calling `initState` again.** A screen that fetches only in
/// `initState` then keeps drawing the previous subject: everything renders, nothing throws, and the
/// numbers belong to something else. Measured on `/locations`, where opening `Storeroom` and then
/// its child `Shelf A` left Storeroom's two products listed under Shelf A's name and its own
/// subtitle correctly saying one.
///
/// `ProductShowView` already carried the `didUpdateWidget` that answers this, with a docblock
/// naming the failure; `LocationShowView` did not. This file exists so the next detail screen
/// cannot repeat it, because no other check can see it: the analyzer is happy, the widget renders,
/// and a screenshot of the wrong products looks exactly like a screenshot of the right ones.
void main() {
  /// A view that reads an id off the route and hands it to a controller.
  final RegExp loadsByRouteId = RegExp(r'\.load\(\s*widget\.id!?\s*[,)]');

  late List<File> detailViews;

  setUpAll(() {
    detailViews = Directory('lib/resources/views')
        .listSync(recursive: true)
        .whereType<File>()
        .where((File f) => f.path.endsWith('.dart'))
        .where((File f) => loadsByRouteId.hasMatch(f.readAsStringSync()))
        .toList();
  });

  test('the detector finds the screens it is meant to check', () {
    // The guard on the guard, matching `route_paths_test`: a scanner that matches nothing reports a
    // clean app forever. The product and location detail screens are both route-id driven.
    expect(detailViews.length, greaterThanOrEqualTo(2));
    expect(
      detailViews.map((File f) => f.uri.pathSegments.last),
      containsAll(<String>['product_show_view.dart', 'location_show_view.dart']),
    );
  });

  test('every screen that loads by a route id reloads when that id changes', () {
    final Iterable<File> offenders = detailViews.where(
      (File f) => !f.readAsStringSync().contains('void didUpdateWidget('),
    );

    expect(
      offenders,
      isEmpty,
      reason: offenders
          .map((File f) => '${f.path} fetches on widget.id and never overrides didUpdateWidget')
          .join('\n'),
    );
  });
}
