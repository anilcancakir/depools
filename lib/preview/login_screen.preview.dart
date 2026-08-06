import 'package:flutter/widgets.dart';
import 'package:magic_starter/magic_starter.dart' show MagicStarterLoginView;

import 'preview_mock_harness.dart';
import 'screen_preview_scaffold.dart';

/// Feature-screen preview: the magic_starter login view rendered backend-free.
class LoginScreenPreview extends StatelessWidget {
  /// Creates the login screen preview.
  const LoginScreenPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const ScreenPreviewScaffold(state: PreviewState.success, builder: _build);
  }

  static Widget _build(BuildContext context) => const MagicStarterLoginView();
}
