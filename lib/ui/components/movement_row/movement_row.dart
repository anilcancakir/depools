import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../quantity/quantity.dart';
import 'movement_row.recipe.dart';

/// Which way a movement pushed stock, which decides its tint and icon.
enum MovementDirection {
  /// Stock came in: a purchase, a transfer in, a return from a customer.
  inbound,

  /// Stock went out through normal use: consumption, a sale, a transfer out.
  outbound,

  /// Stock was discarded: spoiled, broken, expired.
  ///
  /// Its own direction rather than a flavour of [outbound], because waste
  /// percentage and sell-through before expiry are computed by filtering on
  /// exactly this distinction.
  waste,

  /// A correction or a counted adjustment after a stock take.
  correction,
}

/// **MovementRow**
///
/// One entry in the append-only ledger: what happened, who did it, when, and by
/// how much.
///
/// The delta arrives already signed and already formatted, so this widget never
/// does arithmetic or decides a sign. It also means the sign is in the text rather
/// than carried only by the tint, which is what keeps the direction readable for a
/// user who cannot separate the colours.
///
/// **One row, three places.** This renders in a product's own history, in the activity
/// panel across every product, and inside the assistant transcript when a write happens.
/// That is deliberate (D49): three renderings of the same fact are three chances to
/// disagree about it, and undo therefore lives HERE rather than in whichever surface
/// happens to show the movement.
///
/// [note] and [isReversed] are what make that possible. A reversed movement is struck
/// through and keeps its place, because the compensating entry sits beside it and the
/// balance only reconciles by hand if both are visible (D51). [note] carries either the
/// undo affordance's absence-reason or a pointer to the entry that reversed this one.
///
/// ### Example
///
/// ```dart
/// MovementRow(
///   reason: 'Tüketildi', delta: '-1', unit: 'adet',
///   meta: 'Anılcan · bugün 09:14',
///   direction: MovementDirection.outbound,
/// )
/// ```
@immutable
class MovementRow extends StatelessWidget {
  static const Map<MovementDirection, IconData> _icons = {
    MovementDirection.inbound: Icons.add_circle_outline,
    MovementDirection.outbound: Icons.remove_circle_outline,
    MovementDirection.waste: Icons.delete_outline,
    MovementDirection.correction: Icons.tune_outlined,
  };

  /// The already-localised reason label, for example `'Tüketildi'`.
  final String reason;

  /// The raw signed delta, used to pick the tone.
  final num deltaAmount;

  /// The already-signed, already-formatted delta, for example `'-1'` or `'+12'`.
  final String delta;

  /// The product's base unit.
  final String? unit;

  /// The already-formatted actor and timestamp line.
  final String? meta;

  /// Which way this movement pushed stock.
  final MovementDirection direction;

  /// Whether a later correction reversed this entry.
  ///
  /// The row stays in place, struck through. It is not removed and it is not collapsed
  /// into its correction, because the append-only ledger keeps both and
  /// `forecasting.md` asks for balances that reconcile against the visible history by
  /// hand (D51).
  final bool isReversed;

  /// An already-localised trailing note, shown under the meta line.
  ///
  /// Carries the reason an undo is unavailable, or what reversed this entry. It is a
  /// note rather than a disabled button on purpose: a greyed control with no reason is
  /// a dead end, and a disabled `MSButton` is visually indistinguishable from a live one
  /// in this theme, measured.
  final String? note;

  /// The trailing action, normally undo. Absent when there is nothing to offer.
  final Widget? action;

  /// Creates a [MovementRow].
  const MovementRow({
    super.key,
    required this.reason,
    required this.deltaAmount,
    required this.delta,
    required this.direction,
    this.unit,
    this.meta,
    this.isReversed = false,
    this.note,
    this.action,
  });

  /// The delta's tone, mapped from the direction.
  ///
  /// Routed through [Quantity] rather than a hand-rolled mono run, so the value and
  /// unit here match the ones in the lot and location lists on the same screen.
  QuantityTone get _tone {
    switch (direction) {
      case MovementDirection.inbound:
        return QuantityTone.inbound;
      case MovementDirection.waste:
        return QuantityTone.waste;
      case MovementDirection.outbound:
        return QuantityTone.neutral;
      case MovementDirection.correction:
        return QuantityTone.muted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final slots = movementRowRecipe()(
      variants: {'direction': direction.name, 'state': isReversed ? 'reversed' : 'live'},
    );

    return WDiv(
      className: slots['root'],
      children: [
        WDiv(
          className: slots['leading'],
          children: [
            WIcon(_icons[direction]!, className: slots['icon']),
            WDiv(
              className: slots['body'],
              children: [
                WText(reason, className: slots['reason']),
                if (meta != null) WText(meta!, className: slots['meta']),
                if (note != null) WText(note!, className: slots['note']),
              ],
            ),
          ],
        ),
        WDiv(
          className: slots['trailing'],
          children: [
            Quantity(amount: deltaAmount, formatted: delta, unit: unit, tone: _tone),
            ?action,
          ],
        ),
      ],
    );
  }
}
