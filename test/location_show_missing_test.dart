import 'package:depools/app/models/location_node.dart';
import 'package:depools/resources/views/locations/location_show_view.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart' show MSEmptyState;

/// The branch a location that does not resolve falls into.
///
/// **`/locations/:id` matches any segment, so an id the tree does not hold is reachable by typing,
/// by a stale bookmark, and until this was fixed by an ordinary tap on a child row.** The screen
/// answered `SizedBox.shrink()`, whose comment called it "nothing to draw until the tree arrives".
/// That reading is right while the tree is in flight and wrong once it has landed: after that,
/// nothing is all the user ever gets, on a page with no header and no way back.
///
/// The two cases are told apart by whether the tree has ARRIVED, not by whether it is empty, and
/// that is the distinction these tests pin. Driven through the caller-supplied `nodes`, which is
/// the same `_node == null` branch the routed screen takes and the only one reachable without a
/// booted container: `initState` returns early when `id` is null, so no controller is touched.
void main() {
  Future<void> pump(WidgetTester tester, Widget view) async {
    // WindTheme below MaterialApp is wind's own contract (Core Law 8), matching
    // `dashboard_first_run_test.dart`. Strings render as raw keys here because nothing loads the
    // catalogue, which is why these assertions look for the widget rather than for its copy.
    await tester.pumpWidget(
      WindTheme(
        data: WindThemeData(),
        builder: (BuildContext context, WindThemeController controller) => WidgetsApp(
          color: const Color(0xFF000000),
          builder: (BuildContext context, Widget? child) => view,
        ),
      ),
    );
    await tester.pump();
  }

  List<LocationNode> tree() => <LocationNode>[
    LocationNode.of(
      name: 'Storeroom',
      depth: 0,
      productCount: 2,
      summary: '2 products',
      path: 'Storeroom',
      id: '01a05da0-7bb7-713c-8676-bd16ac721616',
    ),
  ];

  testWidgets('a location the arrived tree does not hold says so instead of rendering nothing', (
    tester,
  ) async {
    await pump(
      tester,
      LocationShowView(nodes: tree(), previewPath: 'Storeroom › Shelf A'),
    );

    // The precise regression: this pumped an empty frame, so the assertion that would have caught
    // it is "something is on screen", and `MSEmptyState` is what the screen already uses to say a
    // thing is not there.
    expect(find.byType(MSEmptyState), findsOneWidget);
  });

  testWidgets('a tree that has not arrived stays blank rather than claiming the place is gone', (
    tester,
  ) async {
    // The other half, and the reason the fix is a condition rather than a replacement. Announcing
    // "not found" mid-fetch would tell a user their shelf was deleted every time the network was
    // slow, which is a worse failure than the one being fixed.
    await pump(tester, const LocationShowView(previewPath: 'Storeroom › Shelf A'));

    expect(find.byType(MSEmptyState), findsNothing);
  });
}
