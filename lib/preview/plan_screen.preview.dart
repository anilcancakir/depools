import 'package:flutter/widgets.dart';

import '../resources/views/plan_view.dart';
import 'responsive_screen_preview.dart';

/// The Plan screen, at both widths.
@immutable
class PlanScreenPreview extends StatelessWidget {
  /// Creates the [PlanScreenPreview].
  const PlanScreenPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return ResponsiveScreenPreview(builder: (BuildContext context) => const PlanView());
  }
}
