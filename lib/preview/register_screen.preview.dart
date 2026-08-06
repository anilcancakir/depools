import 'package:flutter/widgets.dart';
import 'package:magic_starter/magic_starter.dart' show MagicStarterRegisterView;

import 'preview_mock_harness.dart';
import 'screen_preview_scaffold.dart';

/// Feature-screen preview: the magic_starter register view rendered
/// backend-free.
class RegisterScreenPreview extends StatelessWidget {
  /// Creates the register screen preview.
  const RegisterScreenPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const ScreenPreviewScaffold(state: PreviewState.success, builder: _build);
  }

  static Widget _build(BuildContext context) => const MagicStarterRegisterView();
}
