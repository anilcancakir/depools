import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../../app/models/app_preferences.dart';

/// The assistant, reachable from every screen (D67).
///
/// ### Why it is persistent rather than a route
///
/// Every capability in this product is meant to be reachable through the assistant: stock
/// movements, adding a product, scanning a barcode. That makes it the layer the app is operated
/// through rather than a feature sitting on it, and an affordance that exists on one route
/// contradicts that. `product.md` states the position; this is the part of it a user can touch.
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
@immutable
class AssistantLauncher extends StatelessWidget {
  static const IconData _icon = Icons.auto_awesome_outlined;

  /// The screen this floats over.
  final Widget child;

  /// Creates an [AssistantLauncher] wrapping [child].
  const AssistantLauncher({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      // Rebuilds when the switch flips, without the settings screen knowing this widget exists.
      listenable: AppPreferences.instance,
      builder: (BuildContext context, Widget? _) {
        if (!AppPreferences.instance.assistantEverywhere) {
          return child;
        }

        return Stack(
          children: <Widget>[
            child,
            Positioned(
              right: 16,
              // Clear of the bottom nav and whatever the device puts under it.
              bottom: 16 + MediaQuery.paddingOf(context).bottom + 64,
              child: WAnchor(
                onTap: () => MagicRoute.to('/asistan'),
                semanticLabel: Lang.get('screens.settings.assistant_open'),
                child: WDiv(
                  className: '''
                    size-14 rounded-full bg-surface-container border border-color-border
                    shadow-md flex items-center justify-center
                  ''',
                  child: const WIcon(_icon, className: 'size-6 text-primary'),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
