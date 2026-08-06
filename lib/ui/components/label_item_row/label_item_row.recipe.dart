import 'package:magic/magic.dart';

/// Builds the [WindSlotRecipe] for the LabelItemRow component.
///
/// Two states, and the printed one recedes rather than disappearing. Criterion 5 makes a
/// partially printed batch resumable, which is only possible if the printed lines stay
/// visible: a jam at label 40 of 96 means the user reprints a range, and a range they
/// cannot see is a range they cannot name.
///
/// The stepper buttons carry their touch target in PADDING, not in `min-h-11`. That is the
/// measured finding already in the anti-pattern table: min-height grows the box downward
/// without re-centring what is inside it.
WindSlotRecipe labelItemRowRecipe() {
  return const WindSlotRecipe(
    slots: {
      'root': 'flex flex-row items-center gap-3 py-2',
      'iconBox': 'size-4 shrink-0 flex items-center justify-center',
      'icon': 'size-4',
      'body': 'flex flex-col gap-0.5 flex-1 min-w-0',
      'name': 'text-sm font-semibold text-fg truncate',
      'meta': 'font-mono text-xs text-fg-muted truncate',
      'stepper': 'flex flex-row items-center gap-1 axis-min',
      'stepButton': 'p-3 rounded-md bg-surface-container-high flex items-center justify-center',
      'stepIcon': 'size-4 text-fg',
      'count': 'font-mono text-sm font-semibold text-fg text-center w-8',
      'fixedCount': 'text-xs text-fg-muted axis-min',
    },
    variants: {
      'state': {
        'pending': {'icon': 'text-fg-muted'},
        'printed': {
          'icon': 'text-fg-disabled',
          'name': 'text-sm font-semibold text-fg-muted truncate',
        },
      },
    },
    defaultVariants: {'state': 'pending'},
  );
}
