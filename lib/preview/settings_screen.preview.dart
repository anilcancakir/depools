import 'package:flutter/widgets.dart';
import 'package:magic_starter/magic_starter.dart' show MagicStarterTeamSettingsView;

import 'preview_mock_harness.dart';
import 'screen_preview_scaffold.dart';

/// Feature-screen preview: the team settings view, authenticated and
/// backend-free.
class SettingsScreenPreview extends StatelessWidget {
  /// Creates the settings screen preview.
  const SettingsScreenPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const ScreenPreviewScaffold(state: PreviewState.success, builder: _build);
  }

  static Widget _build(BuildContext context) => const MagicStarterTeamSettingsView();
}
