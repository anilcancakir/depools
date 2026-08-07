import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart' show Magic;
import 'package:magic_starter/magic_starter.dart'
    show MagicStarterProfileController, MagicStarterProfileSettingsView;

import 'preview_mock_harness.dart';
import 'screen_preview_scaffold.dart';

/// Feature-screen preview: the profile settings view with a sample user,
/// rendered backend-free.
class ProfileScreenPreview extends StatelessWidget {
  /// Creates the profile screen preview.
  const ProfileScreenPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const ScreenPreviewScaffold(state: PreviewState.success, builder: _build);
  }

  /// **The controller has to exist before the view's `initState` looks for it.**
  ///
  /// `MagicStarterProfileSettingsView` is a `MagicView`, so it resolves its controller from the
  /// container in `initState` and throws when nothing is registered. In the app that registration
  /// happens on route entry (`magic_starter`'s `profile_routes.dart` calls `findOrPut` before
  /// building the view), and a preview reaches the view without passing through the route.
  ///
  /// Without this line the preview rendered as a full-bleed red error box, which is how it was
  /// shipped: the catalog listed it, nobody opened it, and `flutter analyze` cannot see a runtime
  /// container lookup. `dusk:exceptions` is what surfaced it.
  ///
  /// `findOrPut` rather than `put`, so navigating to the preview twice reuses the instance instead
  /// of replacing a controller the previous build is still listening to.
  static Widget _build(BuildContext context) {
    Magic.findOrPut(MagicStarterProfileController.new);

    return const MagicStarterProfileSettingsView();
  }
}
