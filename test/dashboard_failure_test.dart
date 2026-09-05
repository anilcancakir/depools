import 'package:depools/resources/views/dashboard_view.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic/testing.dart';
import 'package:magic_starter/magic_starter.dart' show MSEmptyState;

/// What the landing screen does when its one request fails.
///
/// **It rendered `SizedBox.shrink()`**, whose comment reads "nothing until there is an answer, and
/// this screen more than any other". That is right while the request is in flight and wrong once it
/// has come back 500: the controller sets an error with a message nobody reads, and the first thing
/// a user sees after opening the app is an empty page with no explanation and no way to retry.
///
/// The dashboard is the one screen where this matters most, because it is where every session
/// starts and there is nothing else on it to fall back to.
void main() {
  MagicTest.init();

  tearDown(Http.unfake);

  Future<void> pump(WidgetTester tester, Widget view) async {
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

  testWidgets('a failed load says so instead of rendering an empty page', (tester) async {
    Http.fake(
      (MagicRequest request) => MagicResponse(
        statusCode: 500,
        data: const <String, dynamic>{'message': 'Server Error'},
      ),
    );

    // No `summary`, so the view resolves the controller and issues the request its `initState`
    // makes. Two pumps: one to mount, one for the answer.
    await pump(tester, const DashboardView());
    await tester.pump();

    expect(find.byType(MSEmptyState), findsOneWidget);
  });

  testWidgets('a request still in flight stays blank rather than claiming a failure', (
    tester,
  ) async {
    // The other half, and why the fix is a condition rather than a replacement. Announcing a
    // failure while the answer is on its way would show an error on every cold start.
    Http.fake(
      (MagicRequest request) => MagicResponse(
        statusCode: 200,
        data: const <String, dynamic>{
          'data': <String, dynamic>{
            'has_stock': false,
            'products': 0,
            'locations': 0,
            'counters': <String, dynamic>{
              'expired': 0,
              'approaching': 0,
              'out_of_stock': 0,
              'below_target': 0,
              'shopping': 0,
            },
          },
        },
      ),
    );

    await pump(tester, const DashboardView());

    expect(find.byType(MSEmptyState), findsNothing);
  });
}
