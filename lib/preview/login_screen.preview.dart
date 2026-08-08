import 'package:flutter/widgets.dart';
import 'package:magic_starter/magic_starter.dart' show MagicStarterLoginView;

import 'preview_mock_harness.dart';
import 'responsive_screen_preview.dart';

/// Feature-screen preview: the magic_starter login view rendered backend-free.
class LoginScreenPreview extends StatelessWidget {
  /// Creates the login screen preview.
  const LoginScreenPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const ResponsiveScreenPreview(state: PreviewState.success, builder: _build);
  }

  static Widget _build(BuildContext context) => const MagicStarterLoginView();
}
