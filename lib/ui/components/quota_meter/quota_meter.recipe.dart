import 'package:magic/magic.dart';

/// How close a meter is to its limit.
///
/// Three positions rather than a percentage, because the only thing a user needs from a quota is
/// whether they have to do something about it, and a colour ramp over 100 values says nothing a
/// person can act on.
enum QuotaTone {
  /// Plenty of room. The ordinary state, and it should read as unremarkable.
  calm,

  /// Close enough that an upgrade is worth mentioning before it blocks anything.
  near,

  /// At the limit. Everything existing keeps working; only the metered action stops.
  full,
}

/// The slots for [QuotaMeter].
///
/// **The fill has no width token, and that is deliberate.** A proportion is a computed value and
/// Wind's Core Law 3 forbids interpolating one into a `className`: it would break the parser cache
/// and produce a new cache entry per percentage. The recipe paints the fill and a Flutter
/// `FractionallySizedBox` measures it.
///
/// The track is `bg-surface-container-high` rather than a border, because this is not a control:
/// it is a reading, and the input tone is right for a well that something sits inside.
WindSlotRecipe quotaMeterRecipe() {
  return WindSlotRecipe(
    slots: {
      'root': 'flex flex-col gap-1.5 w-full',
      'header': 'flex flex-row items-baseline justify-between gap-2 w-full',
      'label': 'text-sm font-medium text-fg',
      'value': 'text-sm text-fg-muted',
      'track': 'w-full h-2 rounded-full bg-surface-container-high overflow-hidden',
      'fill': 'h-2 rounded-full bg-primary',
      'note': 'text-xs text-fg-muted',
    },
    variants: {
      'tone': {
        // Calm keeps the brand fill: a meter with room is not a status, and tinting it would put a
        // fourth colour meaning on a screen that already has three.
        'calm': {'fill': 'h-2 rounded-full bg-primary'},
        // **The tone lives on the BAR and nowhere else.** Tinting the note as well painted a
        // whole paragraph orange, which a light-mode pass made obvious and which contradicts what
        // this screen is for: `monetization.md` promises that at the limit everything existing
        // keeps working, so the notes say what STOPS rather than what breaks. A sentence in
        // warning colour reads as the second of those.
        //
        // The bar already carries the reading, the fraction is stated as text beside the label,
        // and the note is the same explanatory register as every other note in the app.
        'near': {'fill': 'h-2 rounded-full bg-warning'},
        'full': {'fill': 'h-2 rounded-full bg-destructive'},
      },
    },
    defaultVariants: {'tone': 'calm'},
  );
}
