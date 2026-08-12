import 'package:flutter/widgets.dart';
import 'package:magic_starter/magic_starter.dart' show MSPageScaffold;

import 'page_chrome.dart';

/// [MSPageScaffold] plus a footer that does not scroll away.
///
/// ### The defect it exists for
///
/// Every screen in this app whose point is an action put that action at the END of its scrolling
/// content: the stock take's commit, the scan queue's confirm, the shopping list's actions. On a
/// list that grows without bound, that action is unreachable for exactly the user who needs it
/// most. Anılcan named it on the locations screen, where a SETTING sat under an infinite tree,
/// and the same shape turned out to be under six screens.
///
/// A setting had a second home to move to (`SettingsView`). An action does not: `Sayımı kaydet`
/// belongs to the count in front of you and nowhere else. So it gets pinned instead of moved.
///
/// ### What it costs, and why that is acceptable
///
/// On a phone this stacks a footer above the bottom navigation. Material warns against stacking
/// a Bottom App Bar with a Navigation Bar, and the warning is about a BAR OF ACTIONS competing
/// with destinations. This is one primary action with its own summary, which is the checkout-bar
/// shape iOS and Material both use and which reads as belonging to the page rather than to the
/// app. Keep it to one action, and the warning does not apply.
///
/// ### Where it can be used
///
/// Only inside the app shell. In the preview catalog there is no [PageChromeHost], so [footer]
/// falls back to rendering as the last section, which is what the screen did before. That keeps
/// every screen previewable without a shell and makes the catalog honest about the difference.
class AppPageScaffold extends StatefulWidget {
  /// The page title, forwarded to [MSPageScaffold].
  final String title;

  /// The page subtitle, forwarded to [MSPageScaffold].
  final String? subtitle;

  /// Header actions, forwarded to [MSPageScaffold].
  final List<Widget>? actions;

  /// The back affordance label, forwarded to [MSPageScaffold].
  final String? backLabel;

  /// Where back goes when there is nothing to pop, forwarded to [MSPageScaffold].
  final String? backFallback;

  /// The scrolling sections.
  final List<Widget> children;

  /// The action that stays put while [children] scroll.
  final Widget? footer;

  /// Creates an [AppPageScaffold].
  const AppPageScaffold({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.actions,
    this.backLabel,
    this.backFallback,
    this.footer,
  });

  @override
  State<AppPageScaffold> createState() => _AppPageScaffoldState();
}

class _AppPageScaffoldState extends State<AppPageScaffold> {
  /// The gap `MSPageScaffold` puts between the sections it is given.
  ///
  /// `pageScaffoldChildrenAreaRecipe` is `mt-6 flex flex-col gap-6`, and wind's scale is 4 logical px
  /// a step, so a child inherits 24px of separation before it. The footer reservation subtracts it
  /// rather than stacking on top: see the spacer in [build].
  static const double _scaffoldGap = 24;

  ValueNotifier<Widget?>? _slot;

  /// Whether the footer is being drawn by the host rather than by this page.
  bool get _pinned => _slot != null && widget.footer != null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _slot = PageChrome.of(context);
    _publish();
  }

  @override
  void didUpdateWidget(AppPageScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The footer carries page state ("12 fark"), so it is a new widget on every rebuild and has
    // to be republished rather than published once.
    if (!identical(oldWidget.footer, widget.footer)) _publish();
  }

  @override
  void dispose() {
    // Leaving a footer behind would draw the previous page's action over the next one.
    //
    // **Cleared after the frame rather than inside dispose, for the reason [_publish] records at the
    // other end.** Writing to the notifier here marks the host dirty while the tree is LOCKED, and
    // Flutter throws `setState() or markNeedsBuild() called when widget tree was locked`, naming
    // `PageChrome` and its `ValueListenableBuilder`. It fired on every navigation away from any of
    // the eight screens with a footer, and it was measured rather than assumed: reverting both layout
    // files to their previous state reproduced the identical pair, so it predates this change.
    //
    // Nothing visibly broke, which is why it survived. What it cost is the instrument: a screen's
    // `dusk:exceptions` was never clean, so the check that is supposed to catch a real render fault
    // had two entries in it by default.
    //
    // Guarded on the slot still holding OUR footer, because the ordering between an old page's
    // dispose and a new page's publish is not guaranteed either way. Clearing unconditionally would
    // erase the arriving page's footer when it published first.
    final ValueNotifier<Widget?>? slot = _slot;
    final Widget? mine = widget.footer;

    if (slot != null && mine != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (slot.value == mine) slot.value = null;
      });
    }

    super.dispose();
  }

  /// Hands the footer to the host after the current frame.
  ///
  /// **After, not during.** Writing to the notifier inside `build` or `didChangeDependencies`
  /// marks an ancestor dirty while the tree below it is still building, which Flutter reports as
  /// `setState() or markNeedsBuild() called during build`. One frame of lag is invisible; the
  /// assertion is not.
  void _publish() {
    final ValueNotifier<Widget?>? slot = _slot;
    if (slot == null) return;

    final Widget? footer = widget.footer;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) slot.value = footer;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MSPageScaffold(
      title: widget.title,
      subtitle: widget.subtitle,
      actions: widget.actions,
      backLabel: widget.backLabel,
      backFallback: widget.backFallback,
      children: <Widget>[
        ...widget.children,
        // Room for the pinned footer to sit over, so the last section is not permanently hidden
        // under it.
        //
        // **Measured, not a constant, and the constant was a real defect rather than a tidiness
        // point.** This was `h-20` (80 logical px) while `PageChromeHost` measures the actual footer
        // and folds it into `MediaQuery.padding.bottom` for this subtree, and that file's own
        // docblock says outright that a guessed constant "is wrong by construction: this footer is
        // two lines of summary plus two buttons on one screen and a single button on another".
        //
        // The count screen is where it showed: a summary line, a will-write line and a full-width
        // button clear 80px comfortably, so the LAST row of the count sheet sat permanently under
        // the footer. Unreachable, not merely ugly: a tap at that row's field lands on the footer,
        // so the row could not be counted at all and dusk reported every fill as a success.
        //
        // The number comes from `PageChrome` rather than from `MediaQuery.padding`, and that is the
        // second half of the same defect: the host DOES fold the measured height into the padding,
        // which is what lifts the assistant launcher, but that MediaQuery never reaches a page.
        // Measured here, `MediaQuery.paddingOf(context).bottom` reads 0 while the footer stands over
        // a hundred pixels tall, so reserving from it reserved nothing.
        // Minus the column's own trailing gap, because this spacer is a CHILD of
        // `pageScaffoldChildrenAreaRecipe`'s `flex flex-col gap-6`, so 24 logical px of the room
        // already exists before the spacer starts. Reserving the full inset on top of it stacked the
        // two and left a visible band of nothing under the last card, which Anılcan saw straight
        // away. Clamped at zero so a footer shorter than the gap cannot push the content up.
        if (_pinned)
          SizedBox(
            height: (PageChrome.footerInsetOf(context) - _scaffoldGap).clamp(0, double.infinity),
          ),
        // No host (the preview catalog): render it where it used to live rather than dropping it.
        if (!_pinned && widget.footer != null) widget.footer!,
      ],
    );
  }
}
