/// Turning a ledger entry into words, on the client where the language lives.
///
/// **The server sends an enum and never a sentence**, the same way it sends a unit CODE. It had to
/// be said out loud because the product screen used to render three invented rows reading
/// `Sayım düzeltmesi` and `Zayi: bozuldu`, the same three for every product, on an app whose default
/// locale is English. A server that names the reason in words decides the reader's language from the
/// wrong side of the wire.
library;

import 'package:magic/magic.dart';

import '../../ui/components/movement_row/movement_row.dart' show MovementDirection;

/// The eight reasons `MovementReason` can carry, as the backend spells them.
///
/// Listed here rather than inferred from the response, because a reason this client has never heard
/// of has to render as SOMETHING: the fallback is the raw value, which is ugly and honest, and far
/// better than an empty row that hides an entry from an audit trail.
const List<String> movementReasons = <String>[
  'purchase',
  'consumption',
  'waste',
  'stock_take',
  'correction',
  'transfer_in',
  'transfer_out',
  'return',
];

/// The localised label for a reason.
///
/// Nominal, never imperative: a reason describes what happened and asks for nothing, which is the
/// copy rule this app applies to every state.
String movementReasonLabel(String? reason) {
  if (reason == null || !movementReasons.contains(reason)) {
    // The raw value rather than a guess. An audit trail that silently relabels an entry it does not
    // recognise is worse than one that shows a word the user has to ask about.
    return reason ?? '';
  }

  return Lang.get('components.movement_row.reasons.$reason');
}

/// Which way a reason moves the balance, for the row's icon and tint.
///
/// **Derived from the REASON, not from the sign of the delta**, and the two differ on purpose:
/// waste and a downward correction are both negative and they are not the same event. Reading the
/// sign would collapse them into one arrow, which is precisely the audit distinction the ledger
/// exists to keep.
MovementDirection movementDirection(String? reason, double delta) {
  return switch (reason) {
    'waste' => MovementDirection.waste,
    'stock_take' || 'correction' => MovementDirection.correction,
    'purchase' || 'transfer_in' => MovementDirection.inbound,
    // **`return` is OUTBOUND**, which is not obvious from the word and is settled by the enum's own
    // docblock: "Sent back to the supplier". Grouping it with `purchase` put an inbound arrow and a
    // green tint on stock leaving the building, and because direction is derived from the reason
    // rather than the delta's sign, nothing downstream could have corrected it.
    'consumption' || 'transfer_out' || 'return' => MovementDirection.outbound,
    // An unknown reason still has a sign, so the row can at least point the right way.
    _ => delta < 0 ? MovementDirection.outbound : MovementDirection.inbound,
  };
}

/// Who did it, already localised.
///
/// A person's own name is not translated and the other three actors are: `Assistant` is a word this
/// app owns, `Anılcan` is not. Null for a name with an unknown type is the honest answer rather than
/// a guess at "System".
String? movementActorLabel(String? actorType, String? actorName) {
  if (actorName != null && actorName.trim().isNotEmpty) {
    return actorName;
  }

  if (actorType == null || actorType == 'user') {
    return null;
  }

  return Lang.get('components.movement_row.actors.$actorType');
}
