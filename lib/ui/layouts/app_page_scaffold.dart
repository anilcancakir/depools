import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
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
    _slot?.value = null;
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
        // under it. Without this the footer covers the bottom of the list instead of clearing it.
        if (_pinned) const WSpacer(className: 'h-20'),
        // No host (the preview catalog): render it where it used to live rather than dropping it.
        if (!_pinned && widget.footer != null) widget.footer!,
      ],
    );
  }
}
