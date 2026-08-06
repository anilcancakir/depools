import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import 'stat_card.dart';

/// Static preview for [StatCard].
class StatCardPreview extends StatelessWidget {
  /// Creates the stat-card preview.
  const StatCardPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return WDiv(
      className: 'flex flex-row flex-wrap gap-4 p-6',
      children: const [
        StatCard(label: 'Active users', value: '1,284', delta: '+12% this week'),
        StatCard(label: 'Revenue', value: '\$8,420', delta: '+3.1%'),
        StatCard(label: 'Sessions', value: '42.1k'),
      ],
    );
  }
}
