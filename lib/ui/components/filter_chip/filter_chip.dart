import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import 'filter_chip.recipe.dart';

/// **FilterChip**
///
/// One capsule in the stock list's filter row. Either an offer (a saved filter you
/// could apply) or a statement (a criterion narrowing the list right now).
///
/// The two are the same component because they are the same affordance in two
/// states, and keeping them apart as separate widgets is how they drift into
/// looking alike. Looking alike is the failure: a user who cannot tell what is
/// currently filtering the list reads a shortened list as an empty catalogue.
///
/// [applied] drives both the tint and the × icon. There is no separate `showRemove`
/// flag, because a chip that is applied is always removable and a chip that is not
/// cannot be removed, so two flags would only allow the invalid combinations.
///
/// **[onTap] means different things in the two states, and that is deliberate.**
/// Idle: apply me. Applied: remove me. It is one toggle, so a saved filter's chip
/// turns itself off with a second tap rather than sending the user to "Temizle".
///
/// ### Example
///
/// ```dart
/// FilterChip(label: 'Süresi geçenler', onTap: apply)
/// FilterChip(label: 'Kiler', applied: true, onTap: remove)
/// ```
@immutable
class FilterChip extends StatelessWidget {
  static const IconData _removeIcon = Icons.close_outlined;

  /// The chip text, already localised.
  final String label;

  /// Whether this chip is currently narrowing the list.
  final bool applied;

  /// Apply when idle, remove when [applied].
  final VoidCallback? onTap;

  /// Creates a [FilterChip].
  const FilterChip({super.key, required this.label, this.applied = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final slots = filterChipRecipe()(variants: {'state': applied ? 'applied' : 'idle'});

    return WAnchor(
      onTap: onTap,
      // The × is decoration to a screen reader, so the action has to be spelled out
      // here. Without this the chip announces only "Kiler", which does not say
      // whether tapping it adds or removes that location.
      semanticLabel: applied ? Lang.get('components.filter_chip.remove', {'label': label}) : '$label filtresini uygula',
      child: WDiv(
        className: slots['root'],
        children: [
          WText(label, className: slots['label']),
          if (applied) WIcon(_removeIcon, className: slots['remove']),
        ],
      ),
    );
  }
}
