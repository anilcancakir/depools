import 'package:flutter/widgets.dart';
import 'package:magic_starter/magic_starter.dart' show MagicStarterProfileSettingsView;

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

  static Widget _build(BuildContext context) => const MagicStarterProfileSettingsView();
}
