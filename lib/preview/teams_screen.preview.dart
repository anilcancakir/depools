import 'package:flutter/widgets.dart';
import 'package:magic_starter/magic_starter.dart' show MagicStarterTeamCreateView;

import 'preview_mock_harness.dart';
import 'responsive_screen_preview.dart';

/// Feature-screen preview: the team create view, authenticated and
/// backend-free.
class TeamsScreenPreview extends StatelessWidget {
  /// Creates the teams screen preview.
  const TeamsScreenPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const ResponsiveScreenPreview(state: PreviewState.success, builder: _build);
  }

  static Widget _build(BuildContext context) => const MagicStarterTeamCreateView();
}
