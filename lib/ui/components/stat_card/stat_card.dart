import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import 'stat_card.recipe.dart';

/// **StatCard**
///
/// A generic dashboard stat: a label, a value, and an optional delta line, built
/// from semantic alias tokens. A common app-level building block that
/// magic_starter does not provide, so it is a clean example of an app-owned
/// component.
///
/// ### Example
///
/// ```dart
/// StatCard(label: 'Active users', value: '1,284', delta: '+12% this week')
/// ```
@immutable
class StatCard extends StatelessWidget {
  /// The metric label.
  final String label;

  /// The metric value (already formatted for display).
  final String value;

  /// Optional delta or subtitle line.
  final String? delta;

  /// Creates a [StatCard].
  const StatCard({super.key, required this.label, required this.value, this.delta});

  @override
  Widget build(BuildContext context) {
    return WDiv(
      className: statCardRootClassName(),
      children: [
        WText(label, className: statCardLabelClassName()),
        WText(value, className: statCardValueClassName()),
        if (delta != null) WText(delta!, className: statCardDeltaClassName()),
      ],
    );
  }
}
