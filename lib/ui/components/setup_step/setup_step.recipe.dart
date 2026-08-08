import 'package:magic/magic.dart';

/// Variant axis key for [setupStepRecipe].
const String kSetupStepStateAxis = 'state';

/// Where a setup step stands.
enum SetupStepState {
  /// Not reachable yet, because an earlier step has not been done.
  pending,

  /// The one thing to do next.
  current,

  /// Finished, and kept on screen as evidence rather than removed.
  done,
}

/// Slot classNames for `SetupStep`.
///
/// ### The marker gutter is fixed, and that is what lets the glyph change
///
/// `.claude/rules/design.md` forbids a conditionally-rendered leading glyph, because an icon that
/// appears on some rows and not others shifts the text beside it and destroys the alignment the
/// layout was carrying. A tick replacing a number is exactly that shape, so the marker lives in a
/// `size-8 shrink-0` box: the box is always there and always the same size, and only its CONTENTS
/// change. The title starts at the same x on all three states.
///
/// ### State is carried by tone and by glyph, never by tone alone
///
/// A done step is a tick, a current step is a filled number, a pending step is an outlined number.
/// DESIGN.md's "colour never carries meaning alone" is written about status and applies here too:
/// three rows distinguished only by how blue their circle is are three rows a colour-blind user
/// reads as identical.
///
/// ### Why `current` is the only filled one
///
/// `bg-primary` belongs to one thing in a view. On a setup list the whole point is which step to do
/// NEXT, so that is what earns the fill. A done step is neutral because it is finished, and a
/// pending step is muted because acting on it out of order is not what the screen is asking for.
WindSlotRecipe setupStepRecipe() {
  return const WindSlotRecipe(
    slots: {
      'root': 'flex flex-row items-start gap-3 py-3 w-full',
      // Fixed size, so the number and the tick occupy identical space. `items-center
      // justify-center` centres whichever one is inside.
      'marker': 'flex items-center justify-center size-8 shrink-0 rounded-full',
      'markerText': 'text-sm font-semibold',
      'body': 'flex flex-col gap-1 flex-1 min-w-0',
      'title': 'text-sm font-semibold',
      'description': 'text-xs text-fg-muted',
    },
    variants: {
      kSetupStepStateAxis: {
        'pending': {
          'marker': 'border border-color-border',
          'markerText': 'text-fg-disabled',
          'title': 'text-fg-muted',
        },
        'current': {
          'marker': 'bg-primary',
          'markerText': 'text-on-primary',
          'title': 'text-fg',
        },
        'done': {
          'marker': 'bg-surface-container-high border border-color-border',
          'markerText': 'text-fg-muted',
          'title': 'text-fg-muted',
        },
      },
    },
    defaultVariants: {kSetupStepStateAxis: 'pending'},
  );
}
