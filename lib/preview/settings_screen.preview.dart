import 'package:flutter/widgets.dart';

import '../resources/views/settings_view.dart';
import 'preview_mock_harness.dart';
import 'responsive_screen_preview.dart';

/// Feature-screen preview: this app's own settings.
///
/// Distinct from `ProfileScreen`, which previews `magic_starter`'s account settings. The two are
/// different surfaces with different owners, and the nav entry points here because the preferences
/// D66 and D67 created are this app's rather than the starter's.
class DepoolsSettingsScreenPreview extends StatelessWidget {
  /// Creates the settings preview.
  const DepoolsSettingsScreenPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const ResponsiveScreenPreview(state: PreviewState.success, builder: _build);
  }

  static Widget _build(BuildContext context) => const SettingsView();
}
