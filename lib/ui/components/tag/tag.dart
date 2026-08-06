import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import 'tag.recipe.dart';

/// The tag intent axis.
enum TagIntent {
  /// Muted neutral.
  neutral,

  /// Brand tint.
  primary,

  /// Positive tone.
  success,

  /// Caution tone.
  warning,

  /// Negative tone.
  danger,
}

/// The tag size axis.
enum TagSize {
  /// Compact.
  sm,

  /// Default.
  md,
}

/// **Tag**
///
/// A compact pill for category or status labels, demonstrating a two-axis
/// [WindRecipe] (intent x size). Semantic alias tokens only. An app-owned
/// component: magic_starter does not ship a Tag, so it is a clean example of a
/// component you add on top of the starter set.
///
/// ### Example
///
/// ```dart
/// Tag(intent: TagIntent.success, size: TagSize.md, label: 'Active')
/// ```
@immutable
class Tag extends StatelessWidget {
  /// The visual intent.
  final TagIntent intent;

  /// The size.
  final TagSize size;

  /// The pill text.
  final String label;

  /// Creates a [Tag].
  const Tag({
    super.key,
    required this.label,
    this.intent = TagIntent.neutral,
    this.size = TagSize.sm,
  });

  @override
  Widget build(BuildContext context) {
    return WDiv(
      className: tagRecipe(variants: {'intent': intent.name, 'size': size.name}),
      child: WText(label),
    );
  }
}
