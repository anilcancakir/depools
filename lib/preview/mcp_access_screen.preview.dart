import 'package:flutter/widgets.dart';

import '../resources/views/mcp_access_view.dart';
import 'responsive_screen_preview.dart';

/// The McpAccess screen, at both widths.
@immutable
class McpAccessScreenPreview extends StatelessWidget {
  /// Creates the [McpAccessScreenPreview].
  const McpAccessScreenPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return ResponsiveScreenPreview(builder: (BuildContext context) => const McpAccessView());
  }
}
