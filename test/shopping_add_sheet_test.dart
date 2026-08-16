import 'package:depools/resources/views/products/shopping_add_sheet.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
// `show`, because magic's barrel re-exports a `TextDirection` of its own (wind's) that shadows the
// framework one `Directionality` needs here.
import 'package:magic/magic.dart' show WindTheme;

/// The quantity field, which the E2E pass cannot reach.
///
/// **`dusk:fill` cannot drive an `InputType.number` field on web.** Measured while verifying this
/// sheet: neither `dusk:fill` nor `dusk:press_key` puts anything into it, and removing that one
/// line makes the same fill land immediately. So the browser run drives the name, the submit and
/// the resulting line, and the number lives here, where a test can actually type into it.
///
/// That split is the point rather than a workaround. A number the user typed and a number the
/// sheet submits are two things that can disagree, and the first version of this sheet held a
/// parsed `num` in state and ignored edits it could not parse, so emptying the box left the model
/// on its previous value with the button still live.
void main() {
  Widget wrap(Widget child) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: WindTheme(child: child),
    );
  }

  /// The sheet's own submit path, without the bottom-sheet host.
  ///
  /// `ShoppingAddSheet.show` wraps this in `MSBottomSheet` and reads what `Navigator.pop` carries,
  /// so pumping the body inside a `Navigator` observes exactly the value `show` would return.
  Future<ShoppingAddDraft?> submit(
    WidgetTester tester, {
    required String name,
    required String quantity,
  }) async {
    ShoppingAddDraft? popped;

    await tester.pumpWidget(
      wrap(
        Navigator(
          onGenerateRoute: (RouteSettings settings) => PageRouteBuilder<ShoppingAddDraft>(
            pageBuilder: (_, _, _) => const ShoppingAddSheet(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The route's own result, which is what `MSBottomSheet.show` hands back to the caller.
    final NavigatorState navigator = tester.state<NavigatorState>(find.byType(Navigator));
    ModalRoute.of(tester.element(find.byType(ShoppingAddSheet)))!
        .popped
        .then((Object? value) => popped = value as ShoppingAddDraft?);

    final Finder fields = find.byType(EditableText);

    await tester.enterText(fields.at(0), name);
    await tester.pump();

    await tester.enterText(fields.at(1), quantity);
    await tester.pump();

    // **The raw KEY, not the word.** Nothing loads the catalogue in a widget test, so `Lang.get`
    // returns its argument and the button renders `screens.shopping.add_submit`. That is a fact
    // about the harness, and `dashboard_first_run_test` records the same one; matching the key is
    // honest about it and breaks loudly if the key is ever renamed.
    await tester.tap(find.text('screens.shopping.add_submit'));
    await tester.pumpAndSettle();

    // Nothing popped means the button was disabled, which is an answer rather than a failure.
    if (navigator.canPop()) return null;

    return popped;
  }

  testWidgets('the quantity submitted is the one in the box', (WidgetTester tester) async {
    final ShoppingAddDraft? draft = await submit(tester, name: 'Kağıt havlu', quantity: '4');

    expect(draft?.name, 'Kağıt havlu');
    expect(draft?.quantity, 4);
  });

  testWidgets('one is the prefilled answer, so a name alone is enough', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        Navigator(
          onGenerateRoute: (RouteSettings settings) => PageRouteBuilder<ShoppingAddDraft>(
            pageBuilder: (_, _, _) => const ShoppingAddSheet(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('an emptied box submits nothing rather than the number it used to hold', (
    WidgetTester tester,
  ) async {
    // **The defect the controller removes.** With a parsed `num` in state and an early return on
    // an unparseable edit, clearing the box left the model on `1`: the button stayed live and
    // added one of something, from a field showing nothing. Now the button goes dead with the box.
    final ShoppingAddDraft? draft = await submit(tester, name: 'Kağıt havlu', quantity: '');

    expect(draft, isNull);
  });

  testWidgets('a name of spaces is not a line', (WidgetTester tester) async {
    final ShoppingAddDraft? draft = await submit(tester, name: '   ', quantity: '2');

    expect(draft, isNull);
  });

  testWidgets('the number field drops a comma, so a hand-typed line is whole numbers', (
    WidgetTester tester,
  ) async {
    // **A limitation recorded rather than a behaviour chosen.** Turkish writes `1,5`, and the
    // sheet parses a comma as a decimal point for exactly that reason. It never gets the chance:
    // `InputType.number` filters the comma out before `onChanged` sees it, so `1,5` arrives as
    // `1`. That is wind's field rather than this sheet, and changing it is a PR in that package.
    //
    // Asserted as it is, so the day wind accepts a separator this goes red and somebody re-reads
    // the paragraph instead of rediscovering it. Whole numbers cover a hand-typed shopping line;
    // a weighed amount is a product with a unit, and that path does not come through here.
    final ShoppingAddDraft? draft = await submit(tester, name: 'Un', quantity: '1,5');

    expect(draft?.quantity, 1);
  });

  testWidgets('zero and negatives are refused, because they are not amounts to buy', (
    WidgetTester tester,
  ) async {
    expect(await submit(tester, name: 'Un', quantity: '0'), isNull);
    expect(await submit(tester, name: 'Un', quantity: '-2'), isNull);
  });
}
