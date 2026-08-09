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

  /// An optional action under the message, for example a retry.
  ///
  /// **This is what makes the callout usable as a failure state.** The app's answer to a section
  /// that could not load is to replace that section's body in place and leave the rest of the page
  /// working, which only helps if the replacement offers a way forward. Without an action the user
  /// is told what went wrong and left with a dead end and a page reload.
  ///
  /// Optional because most callouts are notes rather than failures: the MCP screen's read-only
  /// scope note has nothing to act on.
  final Widget? action;

  /// Creates a [Callout].
  const Callout({
    super.key,
    required this.title,
    required this.message,
    this.action,
    this.intent = CalloutIntent.neutral,
  });

  @override
  Widget build(BuildContext context) {
    return WDiv(
      className: calloutRecipe(variants: {'intent': intent.name}),
      children: [
        WText(title, className: 'text-sm font-semibold text-fg'),
        WText(message, className: 'text-sm text-fg-muted'),
        ?action,
      ],
    );
  }
}
