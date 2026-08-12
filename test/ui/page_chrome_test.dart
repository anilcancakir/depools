import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
// `show`, because magic's barrel re-exports a `TextDirection` of its own (wind's) that shadows the
// framework one this file needs for `Directionality`.
import 'package:magic/magic.dart' show WindTheme;

import 'package:depools/ui/layouts/page_chrome.dart';

/// The pinned footer clears whatever is anchored to the bottom edge, including the keyboard.
///
/// **This is the one thing in the bottom-bar change that a dusk run cannot check.** Flutter web
/// reports `MediaQuery.viewInsets.bottom` as 0 because a desktop browser has no soft keyboard, so
/// the whole point of the change (the search field riding above the keys) is invisible in the only
/// environment the E2E driver can reach. A widget test can set the insets directly, which makes
/// this the instrument rather than a supplement to one.
///
/// The failure it pins is silent and total: with the footer left at the navigation's clearance, an
/// open keyboard covers it, so the field the user is typing into is behind the keys they are
/// typing with.
void main() {
  /// Mounts the host with a footer and returns the footer's distance from the bottom edge.
  ///
  /// Measured from the rendered geometry rather than by reading the `Positioned`, because the
  /// question is where the footer ENDED UP: a `bottom:` that something else overrides would still
  /// read correctly off the widget and be wrong on screen.
  Future<double> footerGap(
    WidgetTester tester, {
    required double keyboard,
    required double safeArea,
  }) async {
    const Size size = Size(390, 844);
    const Key footerKey = Key('footer-probe');

    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(
          size: size,
          // **`padding` is DERIVED, and setting the two independently is what made an earlier
          // version of this file pass for the wrong reason.** Flutter's own documentation gives it
          // as `max(0.0, viewPadding - viewInsets)`, so a MediaQuery carrying a 34px padding beside
          // a 20px inset describes a device that does not exist. Modelling it correctly is what
          // turns the small-inset case below into a real check.
          viewPadding: EdgeInsets.only(bottom: safeArea),
          padding: EdgeInsets.only(bottom: math.max(0, safeArea - keyboard)),
          viewInsets: EdgeInsets.only(bottom: keyboard),
        ),
        // The host paints with wind utilities and asks wind whether the window is `lg`, so it
        // needs a theme in context. Defaults are enough: nothing here reads a token VALUE, only
        // the breakpoint predicate and the fact that a theme exists.
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: WindTheme(
            child: PageChromeHost(
              child: _PublishingPage(footer: SizedBox(key: footerKey, height: 64)),
            ),
          ),
        ),
      ),
    );

    // The page publishes after the frame, and the host measures after the one that renders it.
    await tester.pump();
    await tester.pump();

    // Measured against the HOST's own rect rather than the MediaQuery height. The test surface is
    // 800x600 whatever the MediaQuery says, so subtracting the declared 844 read every gap 256
    // pixels too large: a number that looked like a layout bug and was an instrument bug.
    final Rect host = tester.getRect(find.byType(PageChromeHost));
    final Rect rect = tester.getRect(find.byKey(footerKey));

    return host.bottom - rect.bottom;
  }

  // The probe measures the widget a page HANDS to the host, and the host wraps it in its own
  // `px-4 py-3` chrome, so every gap here is 12 larger than the anchor the host sets. Named rather
  // than folded into the expected numbers, because a bare 106 reads as an arbitrary constant and
  // this way a padding change fails with an obvious cause.
  const double footerPadding = 12;

  // 60 for the bottom navigation plus whatever the device puts under it: the arithmetic
  // `_navClearance` already carried, which this change must not disturb.
  const double navAndSafeArea = 60 + 34;

  testWidgets('with no keyboard the footer clears the navigation bar', (WidgetTester tester) async {
    expect(
      await footerGap(tester, keyboard: 0, safeArea: 34),
      closeTo(navAndSafeArea + footerPadding, 0.5),
    );
  });

  testWidgets('an open keyboard lifts the footer onto it', (WidgetTester tester) async {
    // The keyboard covers the navigation bar while it is up, so the gap is the keyboard alone.
    // Summing the two would float the footer a nav-height above the keys, which is why the host
    // takes the larger of the two rather than the total.
    expect(
      await footerGap(tester, keyboard: 336, safeArea: 34),
      closeTo(336 + footerPadding, 0.5),
    );
  });

  testWidgets('a keyboard shorter than the clearance does not pull the footer down', (
    WidgetTester tester,
  ) async {
    // A hardware keyboard attached to a phone reports a small inset for its accessory bar. Two
    // separate ways to get this wrong, and this case catches both: taking the inset unconditionally
    // drops the footer onto the navigation bar, and deriving the clearance from `padding` rather
    // than `viewPadding` drops it by however much the inset ate, here 20 of the 34px safe area.
    expect(
      await footerGap(tester, keyboard: 20, safeArea: 34),
      closeTo(navAndSafeArea + footerPadding, 0.5),
    );
  });
}

/// A minimal page that hands a footer to the host, standing in for `AppPageScaffold`.
///
/// The real scaffold drags in the whole shell (`MSPageScaffold`, the container width, the theme),
/// none of which this measures. What matters is only that a footer reaches the host the same way.
class _PublishingPage extends StatefulWidget {
  final Widget footer;

  const _PublishingPage({required this.footer});

  @override
  State<_PublishingPage> createState() => _PublishingPageState();
}

class _PublishingPageState extends State<_PublishingPage> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final ValueNotifier<Widget?>? slot = PageChrome.of(context);
    // After the frame, for the reason the scaffold's own `_publish` records: writing during build
    // marks an ancestor dirty while the tree below it is still building.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) slot?.value = widget.footer;
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
