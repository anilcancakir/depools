import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import 'expiry_badge.recipe.dart';

/// How close an expiry date is, which decides the badge's tone.
enum ExpiryUrgency {
  /// Already past its date.
  expired,

  /// Inside the attention window.
  urgent,

  /// Far enough out to be informational.
  neutral,
}

/// **ExpiryBadge**
///
/// A lot's expiry date, rendered as a pill whose tone escalates as the date
/// approaches. Pairs an icon with the label so the meaning survives for a user who
/// cannot distinguish the tones, which WCAG 1.4.1 requires and which also keeps
/// `expiring` and `expired` apart when both resolve to red-brown in light mode.
///
/// The urgency is classified from a day count rather than passed in, so every
/// caller draws the same line. [urgentWithinDays] exists because the line is a
/// product decision that differs by domain: a cafe wants three days, a hardware
/// shop may want thirty.
///
/// The label is the caller's, already localised and formatted. This widget never
/// formats a date, because "2 gün" and "12 Eyl" are locale decisions that belong
/// with the rest of the app's formatting.
///
/// ### Example
///
/// ```dart
/// ExpiryBadge(label: '2 gün', daysUntilExpiry: 2)
/// ```
@immutable
class ExpiryBadge extends StatelessWidget {
  static const IconData _expiredIcon = Icons.error_outline;
  static const IconData _urgentIcon = Icons.schedule_outlined;
  static const IconData _neutralIcon = Icons.event_outlined;

  /// The already-formatted, already-localised label, for example `'2 gün'`.
  final String label;

  /// Days from today until the lot expires. Negative means it already has.
  ///
  /// Null means the lot carries no expiry date, which renders nothing at all: an
  /// absent date is not the same as a distant one, and inventing a placeholder
  /// would put a badge on every non-perishable in the list.
  final int? daysUntilExpiry;

  /// The day count at or below which the badge escalates to its urgent tone.
  final int urgentWithinDays;

  /// Optional className appended after the recipe output.
  final String? className;

  /// Creates an [ExpiryBadge].
  const ExpiryBadge({
    super.key,
    required this.label,
    required this.daysUntilExpiry,
    this.urgentWithinDays = 3,
    this.className,
  });

  /// Returns a badge, or null when there is no date to show.
  ///
  /// Use this instead of constructing one and letting it render nothing. A widget
  /// that returns an empty box still occupies a slot in its parent's `children`,
  /// and wind injects a gap separator between all children unconditionally, so a
  /// self-hiding badge left a phantom gap: 4px under the quantity in
  /// `LocationStockRow`'s trailing column, 8px before the lot code in `LotRow`'s
  /// meta row. Rows ended up taller than their siblings and the quantity column
  /// stopped aligning down the list.
  ///
  /// Pair it with a null-aware element so the slot disappears entirely:
  ///
  /// ```dart
  /// children: [?ExpiryBadge.maybe(label: l, daysUntilExpiry: d)]
  /// ```
  static ExpiryBadge? maybe({
    String? label,
    int? daysUntilExpiry,
    int urgentWithinDays = 3,
    String? className,
  }) {
    if (label == null || daysUntilExpiry == null) {
      return null;
    }

    return ExpiryBadge(
      label: label,
      daysUntilExpiry: daysUntilExpiry,
      urgentWithinDays: urgentWithinDays,
      className: className,
    );
  }

  /// The urgency implied by [daysUntilExpiry].
  ExpiryUrgency get urgency {
    final days = daysUntilExpiry;

    if (days == null) {
      return ExpiryUrgency.neutral;
    }

    if (days < 0) {
      return ExpiryUrgency.expired;
    }

    return days <= urgentWithinDays ? ExpiryUrgency.urgent : ExpiryUrgency.neutral;
  }

  IconData get _icon {
    switch (urgency) {
      case ExpiryUrgency.expired:
        return _expiredIcon;
      case ExpiryUrgency.urgent:
        return _urgentIcon;
      case ExpiryUrgency.neutral:
        return _neutralIcon;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (daysUntilExpiry == null) {
      return const WDiv(className: 'hidden');
    }

    return WDiv(
      className: expiryBadgeRecipe()(variants: {'urgency': urgency.name}, className: className),
      children: [
        WIcon(_icon, className: expiryBadgeIconRecipe()()),
        WText(label),
      ],
    );
  }
}
