import 'package:flutter/material.dart' show Icons, Material, MaterialType;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../app/models/app_preferences.dart';
import '../../resources/views/products/assistant_view.dart';

/// The assistant, reachable from every screen and opening over it (D67).
///
/// ### Why it is persistent rather than a route
///
/// Every capability in this product is meant to be reachable through the assistant: stock
/// movements, adding a product, scanning a barcode. That makes it the layer the app is operated
/// through rather than a feature sitting on it, and an affordance that exists on one route
/// contradicts that. `product.md` states the position; this is the part of it a user can touch.
///
/// ### Why it opens as an overlay and not as a push
///
/// The first version navigated to `/asistan`. Anılcan asked for a modal overlay covering the full
/// width and height instead, and the difference is not cosmetic: a push replaces the screen, so
/// asking the assistant about the product you are looking at costs you the product. An overlay
/// keeps that screen alive underneath, so closing returns to the exact scroll position, the exact
/// filter, and the exact row, with no route to restore and no state to carry across.
///
/// It covers the shell rather than sitting inside it, because this widget wraps the layout in
/// `routes/app.dart`. That is what lets it paint over the bottom navigation, which is what makes
/// it a chat window rather than a tab.
///
/// The `/asistan` route stays for the addressable case (a deep link, and the overview's pinned
/// assistant verb). Same screen, two presentations, differing only in the way out: see
/// [AssistantView.onClose].
///
/// ### Why it can be turned off
///
/// The 2026 literature behind D66 is blunt about the cost of a chat affordance for users who would
/// rather click, and one that cannot be dismissed makes that cost permanent. The switch lives in
/// settings; this widget reads it and renders nothing when it is off.
///
/// ### It is deliberately not `bg-primary`
///
/// DESIGN.md allows one primary fill per view, and this thing floats over EVERY view, including the
/// ones whose own primary action is a filled button. A second blue circle on top of `Stok ekle`
/// would make both of them look like the main action. Card tone with a hairline reads as a control
/// in both appearances, which is the same reasoning that took `Reddet` off ghost.
///
/// ### The inset is not decoration
///
/// It clears the shell's bottom navigation and the safe area beneath it. A floating control that
/// overlaps a 44pt tab target steals taps from it, and on a phone the bottom-right corner is
/// exactly where a thumb rests.
class AssistantLauncher extends StatefulWidget {
  /// The screen this floats over.
  final Widget child;

  /// Creates an [AssistantLauncher] wrapping [child].
  const AssistantLauncher({super.key, required this.child});

  @override
  State<AssistantLauncher> createState() => _AssistantLauncherState();
}

class _AssistantLauncherState extends State<AssistantLauncher> {
  static const IconData _icon = Icons.auto_awesome_outlined;

  /// Below this many logical pixels of travel, a scroll is a twitch rather than an intent.
  static const double _threshold = 12;

  bool _open = false;
  bool _visible = true;
  double _lastOffset = 0;

  void _openAssistant() => setState(() => _open = true);

  void _close() => setState(() => _open = false);

  /// Hides the button while the user scrolls down, and brings it back on the way up.
  ///
  /// **This is what makes the button stop covering things.** It floats over the page, so on a
  /// phone it sits on top of whatever the last rows happen to be: in one screenshot it landed
  /// exactly on a `Tüm tarihleri gör` link, which is worse than covering decoration because the
  /// thing underneath was tappable. The other fix is bottom padding on every page, and this app
  /// cannot add that from here: the shell owns the scroll.
  ///
  /// Hiding on the way down is also Material's own answer (`BottomAppBar.setHideOnScroll`), and
  /// it reads as intentional rather than as a control that vanished: reading moves down, and the
  /// gesture that brings it back is the one you already make when you are done reading.
  ///
  /// The threshold is what keeps it from flickering. Without it, the one-pixel jitter of a
  /// momentum scroll settling flips the button on and off.
  bool _onScroll(ScrollNotification notification) {
    // Horizontal scrollers (the filter chip rows) bubble up here too and must not move it.
    if (notification.metrics.axis != Axis.vertical) return false;
    if (notification is! ScrollUpdateNotification) return false;

    final double offset = notification.metrics.pixels;
    final double delta = offset - _lastOffset;
    if (delta.abs() < _threshold) return false;
    _lastOffset = offset;

    // Never hidden at the very top: a page shorter than the viewport would otherwise be able to
    // strand the button after an overscroll bounce.
    final bool next = delta < 0 || offset <= 0;
    if (next != _visible) setState(() => _visible = next);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      // Rebuilds when the switch flips, without the settings screen knowing this widget exists.
      listenable: AppPreferences.instance,
      builder: (BuildContext context, Widget? _) {
        final bool enabled = AppPreferences.instance.assistantEverywhere;

        // Turning the affordance off while the assistant is open would strand it with no way
        // back, so the overlay closes with it.
        if (!enabled && _open) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _close();
          });
        }

        if (!enabled) return widget.child;

        return Stack(
          children: <Widget>[
            // The listener wraps the SHELL rather than a page, because the scroll that matters
            // belongs to the shell: it puts every route inside `flex-1 overflow-y-auto`. Scroll
            // notifications bubble up the tree, so one listener here covers every screen without
            // any of them knowing this exists.
            NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              child: widget.child,
            ),
            if (!_open && _visible) _buildAnchor(context),
            if (_open) _buildOverlay(),
          ],
        );
      },
    );
  }

  /// The floating button, hidden while the assistant it opens is already on screen.
  Widget _buildAnchor(BuildContext context) {
    return Positioned(
      right: 16,
      // Clear of the bottom nav and whatever the device puts under it.
      bottom: 16 + MediaQuery.paddingOf(context).bottom + 64,
      child: WAnchor(
        onTap: _openAssistant,
        semanticLabel: Lang.get('screens.settings.assistant_open'),
        child: WDiv(
          className: '''
            size-14 rounded-full bg-surface-container border border-color-border
            shadow-md flex items-center justify-center
          ''',
          child: const WIcon(_icon, className: 'size-6 text-primary'),
        ),
      ),
    );
  }

  /// The assistant itself, filling the display.
  ///
  /// `Positioned.fill` rather than a sized box: the overlay has to be exactly the window, and the
  /// window is the only thing that knows how big that is. The opaque `bg-surface` is what makes it
  /// modal in practice, since the screen underneath stays mounted and would otherwise show through.
  ///
  /// `PopScope` catches the Android back gesture and the browser back button and turns them into a
  /// close. Without it, back would pop the ROUTE underneath, dismissing the screen the user was on
  /// and leaving the overlay looking like it had eaten the navigation.
  Widget _buildOverlay() {
    return Positioned.fill(
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (bool didPop, Object? _) {
          if (!didPop) _close();
        },
        // `explicitChildNodes` plus a route scope so a screen reader treats this as the current
        // surface instead of reading the list still mounted behind it.
        child: Semantics(
          scopesRoute: true,
          explicitChildNodes: true,
          // **The `Material` is load-bearing and its absence is visible, not silent.** This
          // overlay sits outside `layout.app`, which is what lets it cover the navigation, and
          // the shell is also what was providing the `Material` ancestor every `Text` under a
          // `MaterialApp` needs. Without one, the whole assistant rendered in yellow with
          // double underlines: Flutter's fallback text style, not a theme bug.
          //
          // `MaterialType.transparency` because the fill is wind's job: a colour here would be
          // a raw value outside the token system, and `bg-surface` already carries its `dark:`
          // pair.
          child: Material(
            type: MaterialType.transparency,
            child: WDiv(
              className: 'w-full h-full bg-surface',
              child: AssistantView.fresh(onClose: _close),
            ),
          ),
        ),
      ),
    );
  }
}
