import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../expiry_badge/expiry_badge.dart';
import 'serial_row.recipe.dart';

/// **SerialRow**
///
/// One individually identified unit: its serial, its warranty, and where it came from.
///
/// The serial-tracking counterpart to `LotRow`, and it exists because the two cannot
/// be one component honestly. A lot row's subject is a quantity that can be partly
/// consumed; this row's subject is a specific object that is either here or not. Half
/// a drill does not exist, so there is no amount to render and no fraction to format.
///
/// **The warranty badge is `ExpiryBadge`, not a new one.** A warranty running out and
/// a carton going off are the same shape of problem: a date after which the thing is
/// worth less. Reusing the badge means the severity split (solid means act today, soft
/// means plan) stays consistent across both, and there is one place to change it.
///
/// ### Example
///
/// ```dart
/// SerialRow(
///   serial: 'MK-DHP484-002391',
///   warrantyLabel: '14 gün',
///   warrantyDaysRemaining: 14,
///   receivedLabel: '12 Şub alındı · Mutfak › Depo',
/// )
/// ```
@immutable
class SerialRow extends StatelessWidget {
  /// The serial, IMEI or asset tag.
  final String serial;

  /// The already-formatted warranty label, for example `'14 gün'`.
  final String? warrantyLabel;

  /// Days until the warranty ends. Negative means it has already.
  final int? warrantyDaysRemaining;

  /// The already-formatted acquisition line.
  final String? receivedLabel;

  /// Whether this unit has left. Faded, not removed.
  final bool isGone;

  /// Called when the row is tapped.
  final VoidCallback? onTap;

  /// Creates a [SerialRow].
  const SerialRow({
    super.key,
    required this.serial,
    this.warrantyLabel,
    this.warrantyDaysRemaining,
    this.receivedLabel,
    this.isGone = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final slots = serialRowRecipe()(variants: {'state': isGone ? 'gone' : 'present'});

    return WAnchor(
      onTap: onTap,
      semanticLabel: serial,
      child: WDiv(
        className: slots['root'],
        children: [
          WDiv(
            className: slots['leading'],
            children: [
              WText(serial, className: slots['serial']),
              if (receivedLabel != null) WText(receivedLabel!, className: slots['meta']),
            ],
          ),
          WDiv(
            className: slots['trailing'],
            children: [
              ?ExpiryBadge.maybe(label: warrantyLabel, daysUntilExpiry: warrantyDaysRemaining),
            ],
          ),
        ],
      ),
    );
  }
}
