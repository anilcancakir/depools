import 'package:depools/app/support/icon_catalogue.dart';
import 'package:depools/ui/components/app_icon/app_icon.dart';
import 'package:depools/ui/components/icon_picker/icon_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
// `show`, because magic's barrel re-exports a `TextDirection` of its own (wind's) that shadows the
// framework one `Directionality` needs here.
import 'package:magic/magic.dart' show WindTheme;

/// A selection made OUTSIDE the grid still has to be on screen.
///
/// There are two ways to make one and neither goes through a tile: the automatic suggestion on the
/// location form, and opening the form for a location that already has an icon. The grid shows the
/// fifty most popular for an empty query, so anything outside that fifty left the screen saying an
/// icon was chosen while showing no chosen icon. Measured on a real run: `ac_unit` was suggested,
/// the note said so, and the grid highlighted nothing.
void main() {
  const String svg = '<svg viewBox="0 0 24 24"><path d="M0 0h24v24H0z"/></svg>';

  CatalogueIcon icon(String name) => CatalogueIcon(name: name, title: name, svg: svg);

  /// A catalogue that answers a fixed search and holds whatever it is given.
  ///
  /// Subclassed rather than mocked, the same way the preview's stub is: `remember` is the seam the
  /// component's own author left for exactly this, and a fake implementing the class from scratch
  /// would have to reimplement `held`.
  ///
  /// **`search` is overridden so nothing reaches `Http`.** Without it the widget's `initState` fires
  /// a real request under the test binding, which is a failure with a URL in it rather than a
  /// meaningful assertion.
  Widget wrap(_FakeCatalogue catalogue, {String? selected}) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: WindTheme(
        child: IconPicker(
          selected: selected,
          onSelected: (String _) {},
          searchPlaceholder: 'Search icons',
          searchingLabel: 'Searching',
          emptyLabel: 'No matching icon',
          catalogue: catalogue,
        ),
      ),
    );
  }

  testWidgets('a selected icon the search did not return is pinned first', (WidgetTester tester) async {
    final _FakeCatalogue catalogue = _FakeCatalogue(<CatalogueIcon>[icon('home'), icon('star')]);
    catalogue.hold(icon('ac_unit'));

    await tester.pumpWidget(wrap(catalogue, selected: 'ac_unit'));
    await tester.pumpAndSettle();

    final List<String> shown = _tiles(tester);

    expect(shown.first, 'ac_unit', reason: 'the chosen icon has to be the first thing in the grid');
    expect(shown, containsAll(<String>['home', 'star']));
  });

  testWidgets('a selected icon the search DID return is left in its own ranking', (WidgetTester tester) async {
    // Moving a result out of its ranking to the front would make the grid reorder itself under the
    // user's cursor, which is worse than the problem being solved.
    final _FakeCatalogue catalogue = _FakeCatalogue(<CatalogueIcon>[icon('home'), icon('star')]);

    await tester.pumpWidget(wrap(catalogue, selected: 'star'));
    await tester.pumpAndSettle();

    final List<String> shown = _tiles(tester);

    expect(shown, <String>['home', 'star']);
  });

  testWidgets('a search that matched nothing still shows what is chosen', (WidgetTester tester) async {
    // The state where knowing what is currently chosen matters most: the user is one bad query away
    // from losing sight of it, and the empty-results branch used to replace the grid entirely.
    final _FakeCatalogue catalogue = _FakeCatalogue(const <CatalogueIcon>[]);
    catalogue.hold(icon('ac_unit'));

    await tester.pumpWidget(wrap(catalogue, selected: 'ac_unit'));
    await tester.pumpAndSettle();

    expect(find.text('No matching icon'), findsNothing);
  });

  testWidgets('nothing chosen renders the results alone', (WidgetTester tester) async {
    final _FakeCatalogue catalogue = _FakeCatalogue(<CatalogueIcon>[icon('home')]);

    await tester.pumpWidget(wrap(catalogue));
    await tester.pumpAndSettle();

    final List<String> shown = _tiles(tester);

    expect(shown, <String>['home']);
  });
}

/// The names in the grid, in the order they are drawn.
///
/// Read from [AppIcon] rather than from the semantics tree, which also carries the search field's
/// placeholder and repeats a tile's label on its nested nodes.
List<String> _tiles(WidgetTester tester) => tester
    .widgetList<AppIcon>(find.byType(AppIcon))
    .map((AppIcon icon) => icon.name ?? '')
    .toList();

class _FakeCatalogue extends IconCatalogue {
  _FakeCatalogue(this._results) {
    for (final CatalogueIcon icon in _results) {
      remember(icon);
    }
  }

  final List<CatalogueIcon> _results;

  /// Hold an icon the search will not return.
  ///
  /// Wraps `remember`, which is `@protected`: the annotation allows a SUBCLASS to call it from its
  /// own instance member, which is exactly what this is, and calling it from the test body directly
  /// is the warning `flutter analyze` raises.
  void hold(CatalogueIcon icon) => remember(icon);

  @override
  Future<List<CatalogueIcon>> search(String query) async => _results;

  @override
  Future<CatalogueIcon?> resolve(String name) async => held(name);
}
