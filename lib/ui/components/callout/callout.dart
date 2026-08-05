import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import 'callout.recipe.dart';

/// The callout intent axis.
enum CalloutIntent {
  /// Muted neutral note.
  neutral,

  /// Informational (brand tint).
  info,

  /// Negative / warning note.
  danger,
}

/// **Callout**
///
/// An inline note with a title and message, tinted by intent. Demonstrates a
/// single-axis [WindRecipe] on a composed widget. Semantic alias tokens only. An
/// app-owned component not shipped by magic_starter.
///
/// ### Example
///
/// ```dart
/// Callout(
///   intent: CalloutIntent.info,
///   title: 'Heads up',
///   message: 'This is an inline callout built from a single-axis recipe.',
/// )
/// ```
@immutable
class Callout extends StatelessWidget {
  /// The visual intent.
  final CalloutIntent intent;

  /// The bold headline.
  final String title;

  /// The body message.
  final String message;

  /// Creates a [Callout].
  const Callout({
    super.key,
    required this.title,
    required this.message,
    this.intent = CalloutIntent.neutral,
  });

  @override
  Widget build(BuildContext context) {
    return WDiv(
      className: calloutRecipe(variants: {'intent': intent.name}),
      children: [
        WText(title, className: 'text-sm font-semibold text-fg'),
        WText(message, className: 'text-sm text-fg-muted'),
      ],
    );
  }
}
