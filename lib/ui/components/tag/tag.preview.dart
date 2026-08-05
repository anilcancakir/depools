import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import 'tag.dart';

/// Static preview for [Tag]: every intent at both sizes.
class TagPreview extends StatelessWidget {
  /// Creates the tag preview.
  const TagPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return WDiv(
      className: 'flex flex-col gap-4 p-6',
      children: [
        for (final size in TagSize.values)
          WDiv(
            className: 'flex flex-row flex-wrap items-center gap-3',
            children: [
              for (final intent in TagIntent.values)
                Tag(intent: intent, size: size, label: intent.name),
            ],
          ),
      ],
    );
  }
}
