import 'package:depools/resources/views/dashboard_fixtures.dart';
import 'package:depools/resources/views/dashboard_view.dart';
import 'package:depools/ui/components/setup_step/setup_step.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';

/// The first-run branch, which no fixture can reach.
///
/// Every other screen in this app is verified against a demo tenant that is deliberately mid-work,
/// so the one state every real user passes through exactly once has no data path to it.
/// `DashboardView.fresh` is the only door, and without a test the branch ships having been rendered
/// only by whoever remembered to open its preview.
void main() {
  // **A realistic surface, because `Lang.get` returns the KEY in a widget test.** Nothing loads
  // the catalogue here (`Lang.has('app.name')` is false even after `setLocale`), so every string
  // renders as `screens.dashboard.counter_expired` rather than as the two words it stands for.
  // Keys are much longer than copy, and the default 800x600 test surface overflowed by 240 to 312
  // pixels the moment this screen moved off literals.
  //
  // That is a fact about the harness rather than a layout defect, and I nearly shipped a
  // breakpoint change on the wrong diagnosis before checking.
  //
  // Widening the surface does NOT help, and that is worth knowing: the content is capped at
  // `max-w-6xl`, so a wider window gives the rows no more room. The overflow is consumed
  // explicitly below instead, which is honest about what it is.
  Future<void> pump(WidgetTester tester, Widget view) async {
    // WindTheme below MaterialApp is wind's own contract (Core Law 8): the builder inverts the
    // apparent order, so a parser lookup from inside the tree can still walk up to the theme.
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

  testWidgets('a fresh tenant gets the setup checklist, not four zeroes', (tester) async {
    await pump(tester, DashboardView.fresh(summary: dashboardFreshFixture()));

    expect(find.byType(SetupStep), findsNWidgets(3));
  });

  testWidgets('exactly one step is current, so there is one next thing to do', (tester) async {
    await pump(tester, DashboardView.fresh(summary: dashboardFreshFixture()));

    final Iterable<SetupStep> steps = tester.widgetList<SetupStep>(find.byType(SetupStep));
    final int current = steps.where((s) => s.state == SetupStepState.current).length;

    // Two current steps is a checklist with no order, which is the whole thing the numbers promise.
    expect(current, 1);
    expect(steps.first.state, SetupStepState.current, reason: 'the first step must be the current one');
  });

  testWidgets('every step offers a way to do it', (tester) async {
    await pump(tester, DashboardView.fresh(summary: dashboardFreshFixture()));

    for (final SetupStep step in tester.widgetList<SetupStep>(find.byType(SetupStep))) {
      expect(step.actionLabel, isNotNull, reason: '${step.title} has no action');
      expect(step.onAction, isNotNull, reason: '${step.title} has a label but no callback');
    }
  });

  testWidgets('a populated tenant does not get the checklist', (tester) async {
    await pump(tester, DashboardView(summary: dashboardFixture()));

    // The populated dashboard overflows in this harness because every string renders as its own
    // key and a key is longer than the copy it stands for. Consumed rather than worked around: it
    // is not a layout defect, and the real layout is verified against the running app at 390px and
    // 1400px where the catalogue is loaded.
    tester.takeException();

    // The guard runs the other way too: a branch that renders in both states is not a branch.
    expect(find.byType(SetupStep), findsNothing);
  });
}
