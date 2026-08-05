import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import 'callout.dart';

/// Static preview for [Callout]: every intent.
class CalloutPreview extends StatelessWidget {
  /// Creates the callout preview.
  const CalloutPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return WDiv(
      className: 'flex flex-col gap-4 p-6',
      children: const [
        Callout(
          intent: CalloutIntent.neutral,
          title: 'Neutral note',
          message: 'A muted callout on the high-contrast surface tone.',
        ),
        Callout(
          intent: CalloutIntent.info,
          title: 'Heads up',
          message: 'An informational callout tinted with the brand container.',
        ),
        Callout(
          intent: CalloutIntent.danger,
          title: 'Something needs attention',
          message: 'A danger callout tinted with the destructive container.',
        ),
      ],
    );
  }
}
