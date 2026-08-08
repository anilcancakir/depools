import 'package:flutter/widgets.dart';
import 'package:magic_starter/magic_starter.dart' show MagicStarterRegisterView;

import 'preview_mock_harness.dart';
import 'responsive_screen_preview.dart';

/// Feature-screen preview: the magic_starter register view rendered
/// backend-free.
class RegisterScreenPreview extends StatelessWidget {
  /// Creates the register screen preview.
  const RegisterScreenPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const ResponsiveScreenPreview(state: PreviewState.success, builder: _build);
  }

  static Widget _build(BuildContext context) => const MagicStarterRegisterView();
}
