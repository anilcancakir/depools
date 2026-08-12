import 'dart:math' as math;

import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart' show MagicStarter;

/// Carries the pinned footer a page wants, from inside the shell's scroll to outside it.
///
/// ### Why a scope and a host instead of a Column
///
/// The obvious way to pin a footer is `Column(children: [Expanded(scroll), footer])`, and it
/// cannot be done from a page in this app. `magic_starter`'s shell puts every route inside
/// `WDiv(className: 'flex-1 overflow-y-auto')`, so a page is handed UNBOUNDED height: an
/// `Expanded` there fails as `RenderBox was not laid out`, which names nothing.
///
/// What does work is what the assistant launcher already proved: wrap OUTSIDE
/// `layout.app`, where the box is the window and a `Stack` can anchor to the viewport. So the
/// footer travels up rather than being laid out in place. The page declares it, this scope
/// carries it, and [PageChromeHost] draws it over the shell.
///
/// The alternative was a `footer:` slot on `MSPageScaffold` itself, which is the better home and
/// is a PR in another repository plus a publish cycle. The call site here is deliberately the
/// same shape (`footer:`), so adopting the upstream version later deletes this file and changes
/// nothing else.
class PageChrome extends InheritedNotifier<ValueNotifier<Widget?>> {
  /// How much vertical room the pinned footer occupies at the bottom of the viewport, in logical
  /// pixels: its measured height plus the inset it is anchored at. Zero when nothing is pinned.
  ///
  /// **Published here because the host's `MediaQuery` does not reach the page.** [PageChromeHost]
  /// folds the measured height into `MediaQuery.padding.bottom` for its subtree, and that is what
  /// lifts the assistant launcher. A page cannot use it: measured on the count screen,
  /// `MediaQuery.paddingOf` inside [AppPageScaffold] reads 0 while the footer stands well over a
  /// hundred pixels tall, so the space a page reserved from it was nothing at all and the last row
  /// of the count sheet sat under the footer. Unreachable rather than merely hidden, because a tap
  /// at that row lands on the footer instead.
  ///
  /// It carries the anchor inset as well as the height, so a page clears the same total the footer
  /// actually occupies and neither side has to know the other's arithmetic.
  final double footerInset;

  /// Creates a [PageChrome] carrying [notifier] to its subtree.
  const PageChrome({
    super.key,
    required ValueNotifier<Widget?> notifier,
    required this.footerInset,
    required super.child,
  }) : super(notifier: notifier);

  /// The nearest chrome slot, or null outside a [PageChromeHost].
  ///
  /// Null is a legitimate answer rather than an error: the preview catalog renders screens with
  /// no shell around them, and a screen that cannot pin its footer there should still build.
  static ValueNotifier<Widget?>? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PageChrome>()?.notifier;

  /// How much room to leave at the end of a page's content so the pinned footer clears it.
  ///
  /// Zero outside a host, which is right: with no host the footer renders as the last section and
  /// occupies real space rather than floating over anything.
  static double footerInsetOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PageChrome>()?.footerInset ?? 0;

  @override
  bool updateShouldNotify(covariant PageChrome oldWidget) =>
      super.updateShouldNotify(oldWidget) || oldWidget.footerInset != footerInset;
}

/// Draws the current page's pinned footer over the app shell.
///
/// Mounted in `routes/app.dart` outside `layout.app`, for the reason [PageChrome] explains.
///
/// The bottom inset clears the navigation bar and whatever the device puts under it, using the
/// same arithmetic the assistant launcher uses. A footer that overlapped a 44pt tab target would
/// steal taps from it, and on a phone the bottom edge is exactly where a thumb rests.
class PageChromeHost extends StatefulWidget {
  /// The shell this draws over.
  final Widget child;

  /// Creates a [PageChromeHost] wrapping [child].
  const PageChromeHost({super.key, required this.child});

  @override
  State<PageChromeHost> createState() => _PageChromeHostState();
}

class _PageChromeHostState extends State<PageChromeHost> {
  /// How far above the bottom edge the footer is anchored, clearing the navigation bar.
  ///
  /// **60, and the 2 logical pixels of overlap are the point.** The shell's bottom navigation has
  /// no fixed height: it is its item content plus the device's safe area, measured at 62 logical px
  /// on a 390px viewport. Sitting at 64 left a 2px strip between the footer and the nav, and the
  /// scrolling list showed through it, which reads as a rendering glitch rather than as chrome.
  ///
  /// Overlapping is the safe direction of the two. The footer's own hairline lands on the nav's
  /// hairline, which is invisible because both are `bg-surface` with the same border token; a gap is
  /// never invisible.
  ///
  /// Named rather than written twice, because the page's reserved space is derived from it: the two
  /// sitting in different files as the same literal is how they would drift apart.
  static const double _navClearance = 60;

  /// How far above the bottom edge the footer sits, which is zero without a bottom navigation.
  ///
  /// **The clearance used to be unconditional, and above `lg` there is nothing to clear.** The shell
  /// puts navigation in the left sidebar at desktop width and renders no bottom bar at all
  /// (`magic_starter_app_layout.dart` gates it on the same `wScreenIs(context, 'lg')`), so 60 pixels
  /// were being reserved for a widget that was not there. It left a strip under the footer with the
  /// scrolling list visible through it: measured on the shopping list, a basket row rendered BELOW
  /// the footer's own fill, which reads as a rendering fault rather than as chrome.
  ///
  /// Read through wind's own predicate rather than a width literal, because the shell decides with
  /// that predicate. A number here would be the same decision written twice.
  ///
  /// **`viewPadding` and not `padding`, because `padding` shrinks when a keyboard opens.** Flutter
  /// computes it as `max(0, viewPadding - viewInsets)`, so reading it here made the clearance a
  /// function of the keyboard: a small inset, which is what a hardware keyboard's accessory bar
  /// reports, took `padding.bottom` from 34 to 14 and dropped the footer 20 pixels ONTO the
  /// navigation bar. The safe area does not move when the keyboard appears, and this is the value
  /// that says so.
  double _clearance(BuildContext context) =>
      wScreenIs(context, 'lg') ? 0 : _navClearance + MediaQuery.viewPaddingOf(context).bottom;

  /// Where the footer's bottom edge actually sits, measured from the bottom of the window.
  ///
  /// **One method because two callers, and they were drifting the moment the keyboard arrived.**
  /// The `Positioned` took the keyboard into account and the published [PageChrome.footerInset] did
  /// not, so with a 336px keyboard over a 94px clearance a page reserved 242 pixels less than the
  /// footer occupied and its last row sat underneath the lifted bar. Unreachable rather than merely
  /// hidden, which is the exact defect [PageChrome.footerInset] exists to prevent, reintroduced one
  /// layer up.
  ///
  /// The keyboard wins over the clearance rather than adding to it, because it covers the
  /// navigation bar while it is up.
  double _anchor(BuildContext context) => math.max(
    _clearance(context),
    MediaQuery.viewInsetsOf(context).bottom,
  );

  final ValueNotifier<Widget?> _footer = ValueNotifier<Widget?>(null);
  final GlobalKey _footerKey = GlobalKey();

  double _footerHeight = 0;

  @override
  void dispose() {
    _footer.dispose();
    super.dispose();
  }

  /// Measures the footer after it lays out, so everything else can clear it.
  ///
  /// **The measurement is what keeps the floating assistant button off the footer.** Both are
  /// anchored to the viewport, and the button's inset is a constant, so a footer taller than that
  /// constant lands underneath it. Rather than teach the button about footers, the height is
  /// folded into `MediaQuery.padding.bottom` for the whole subtree: the button already reads that
  /// padding to clear the navigation bar, so it lifts by exactly the right amount and needs to
  /// know nothing.
  ///
  /// A guessed constant was the alternative and it is wrong by construction: this footer is two
  /// lines of summary plus two buttons on one screen and a single button on another.
  void _measure() {
    final RenderObject? box = _footerKey.currentContext?.findRenderObject();
    final double next = box is RenderBox && box.hasSize ? box.size.height : 0;
    if ((next - _footerHeight).abs() < 0.5) return;
    if (mounted) setState(() => _footerHeight = next);
  }

  @override
  Widget build(BuildContext context) {
    return PageChrome(
      notifier: _footer,
      // Zero until the footer has been measured, and zero again once it is gone, so a page with no
      // footer reserves nothing. The one frame between publishing a footer and measuring it reserves
      // nothing either, which is invisible.
      footerInset: _footerHeight == 0 ? 0 : _footerHeight + _anchor(context),
      child: ValueListenableBuilder<Widget?>(
        valueListenable: _footer,
        builder: (BuildContext context, Widget? footer, Widget? _) {
          if (footer == null) {
            // Reset, or the next page keeps clearing a footer that is no longer there.
            if (_footerHeight != 0) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _footerHeight = 0);
              });
            }
            return widget.child;
          }

          WidgetsBinding.instance.addPostFrameCallback((_) => _measure());

          final MediaQueryData media = MediaQuery.of(context);

          return Stack(
            children: <Widget>[
              MediaQuery(
                data: media.copyWith(
                  padding: media.padding.copyWith(
                    bottom: media.padding.bottom + _footerHeight,
                  ),
                ),
                child: widget.child,
              ),
              Positioned(
                // **The footer belongs to the PAGE, so on desktop it starts where the page does.**
                // Anchored at 0 it spanned the whole window, and once it sat flush to the bottom edge
                // it covered the sidebar's account block, which is a tappable control. The number is
                // the shell's own `sidebarWidth` rather than a literal, so the two cannot drift; below
                // `lg` there is no sidebar and the footer spans the full width, which is right.
                left: wScreenIs(context, 'lg')
                    ? MagicStarter.manager.layoutTheme.sidebarWidth
                    : 0,
                right: 0,
                // See [_anchor], which the published `footerInset` reads too so a page reserves
                // exactly what the footer occupies. `viewInsets` is zero on Flutter web, correctly
                // (a desktop browser has no soft keyboard), which is also why the keyboard half of
                // this cannot be verified in a dusk run and has a widget test instead.
                bottom: _anchor(context),
                // The `Material` is the same one the assistant overlay needed, for the same
                // reason: this draws OUTSIDE `layout.app`, which is what was providing the
                // ancestor every `Text` under a `MaterialApp` resolves its style from. Without
                // it the whole footer renders in Flutter's yellow double-underlined fallback,
                // which looks like a theme bug and is not one.
                //
                // The fill and the hairline are what separate it from the content sliding
                // underneath. Without them the footer reads as a row that happens to be there
                // rather than as chrome, and the list scrolls through it illegibly.
                child: Material(
                  type: MaterialType.transparency,
                  child: WDiv(
                    key: _footerKey,
                    className: 'w-full bg-surface border-t border-color-border px-4 py-3',
                    child: footer,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
