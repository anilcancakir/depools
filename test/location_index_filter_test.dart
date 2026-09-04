import 'package:depools/app/models/location_node.dart';
import 'package:depools/resources/views/locations/location_index_view.dart';
import 'package:depools/ui/components/location_row/location_row.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic/testing.dart';
import 'package:magic_starter/magic_starter.dart' show MSInput, MSSegmentedControl;

/// The two controls above the location tree, which looked live and did nothing.
///
/// **Both were `onChanged: (_) {}`.** The field accepted text and the segmented control accepted a
/// tap, and the six rows underneath never moved: typing `Fridge` left every location on screen, and
/// the scope control did not even change its own selection. A control that cannot be used is worse
/// than an absent one, because the user spends the tap finding out, and this screen's own search
/// field carries a comment saying exactly that about the `WDiv` it replaced.
///
/// Driven through the caller-supplied `nodes`, which is the offline path: `initState` returns early
/// when a tree is handed in, so no controller and no container are needed.
void main() {
  // The placement dial above the tree reads `AppPreferences`, which resolves `cache` out of the
  // container, so the screen cannot be pumped without one: without this the dial throws
  // "Service [cache] is not registered" and the real assertion is buried under it.
  MagicTest.init();

  setUp(Cache.fake);

  Future<void> pump(WidgetTester tester, Widget view) async {
    // WindTheme below MaterialApp is wind's own contract (Core Law 8), matching
    // `dashboard_first_run_test.dart`.
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

  LocationNode node(String name, String path, int productCount) => LocationNode.of(
    name: name,
    depth: path.contains('›') ? 1 : 0,
    productCount: productCount,
    summary: '',
    path: path,
    id: 'id-$name',
  );

  List<LocationNode> tree() => <LocationNode>[
    node('Kitchen', 'Kitchen', 0),
    node('Fridge', 'Kitchen › Fridge', 4),
    node('Buzdolabı', 'Kitchen › Buzdolabı', 2),
    node('Storeroom', 'Storeroom', 0),
  ];

  testWidgets('typing narrows the tree to the matching places', (tester) async {
    await pump(tester, LocationIndexView(nodes: tree()));

    expect(find.byType(LocationRow), findsNWidgets(4));

    await tester.enterText(find.byType(MSInput), 'fridge');
    await tester.pump();

    expect(find.byType(LocationRow), findsOneWidget);
  });

  testWidgets('a search matches on the path, so a child is findable by its parent', (tester) async {
    // The path is what the filtered list renders in place of the indent, so it is also what the
    // user can see to search for. Two of these four sit under Kitchen and Kitchen itself matches.
    await pump(tester, LocationIndexView(nodes: tree()));

    await tester.enterText(find.byType(MSInput), 'kitchen');
    await tester.pump();

    expect(find.byType(LocationRow), findsNWidgets(3));
  });

  testWidgets('a Turkish name is findable typed without its diacritics', (tester) async {
    // `Buzdolabı` ends in a dotless i, and nobody types one on a search field. Dart's `toLowerCase`
    // is locale-independent, so it leaves `ı` alone and a plain contains would miss the row: the
    // failure is a shelf the user can see and cannot find.
    await pump(tester, LocationIndexView(nodes: tree()));

    await tester.enterText(find.byType(MSInput), 'buzdolabi');
    await tester.pump();

    expect(find.byType(LocationRow), findsOneWidget);
  });

  testWidgets('the scope control narrows to the places that hold something', (tester) async {
    await pump(tester, LocationIndexView(nodes: tree()));

    // Index 1 is `stocked`, the middle of the three the screen renders in enum order.
    // Typed, because the screen renders two segmented controls: this one and the placement dial.
    final MSSegmentedControl<LocationScope> control = tester.widget(
      find.byType(MSSegmentedControl<LocationScope>),
    );
    control.onChanged?.call(1);
    await tester.pump();

    expect(find.byType(LocationRow), findsNWidgets(2));
  });

  testWidgets('scope and search compose rather than replacing each other', (tester) async {
    // The regression this guards is a filter that resets the other one: two controls over one list
    // have to intersect, or picking a scope silently throws away what the user typed.
    await pump(tester, LocationIndexView(nodes: tree()));

    await tester.enterText(find.byType(MSInput), 'kitchen');
    await tester.pump();

    // Typed, because the screen renders two segmented controls: this one and the placement dial.
    final MSSegmentedControl<LocationScope> control = tester.widget(
      find.byType(MSSegmentedControl<LocationScope>),
    );
    control.onChanged?.call(1);
    await tester.pump();

    // Kitchen itself holds nothing, so `stocked` plus `kitchen` leaves the two shelves inside it.
    expect(find.byType(LocationRow), findsNWidgets(2));
  });
}
