import 'package:magic/magic.dart';

/// Builds the [WindRecipe] for the ExpiryBadge component.
///
/// Tones come from the status supplement in `lib/config/depools_status_tokens.dart`,
/// so `bg-expired-soft` and `text-expired-soft-foreground` already carry their own
/// light/dark pair and no explicit `dark:` peer belongs here.
///
/// Only the two urgent tones carry a fill. A date far enough out is information,
/// not a status, so it renders as muted text with no chip at all.
///
/// That is not only a hierarchy argument. A filled neutral chip has no background
/// that survives every context: `bg-surface-container-high` disappears the moment
/// the badge sits inside a panel already using that token, which is exactly what
/// happened on the product detail screen. Dropping the fill removes the collision
/// instead of trading one wrong parent for another.
///
/// The horizontal padding stays on every variant so a list of mixed urgencies keeps
/// its labels on one vertical line.
///
/// **Expired is a solid fill, urgent is a soft one, and that is deliberate.** In
/// light mode Apple's increased-contrast orange (#A82B00) and red (#D70015) both
/// resolve to brown-red and sit close enough that a soft chip of each is hard to
/// tell apart at a glance. That was visible the moment both rendered side by side.
/// The fix is severity, not hue: "already expired" and "expires today" demand
/// different actions, so they get different weights. A weight difference also
/// survives colour blindness, where a hue shift would not.
///
/// `WBadge` is deliberately not reused: it composes a single [WText] and has no
/// icon slot, while every status here must pair its colour with an icon and a
/// label per WCAG 1.4.1. Colour is never the only carrier.
WindRecipe expiryBadgeRecipe() {
  return const WindRecipe(
    base: 'flex flex-row items-center gap-1 rounded-full px-2 py-0.5 text-xs font-medium',
    variants: {
      'urgency': {
        'expired': 'bg-expired text-on-destructive',
        'urgent': 'bg-expiring-soft text-expiring-soft-foreground',
        'neutral': 'text-fg-muted',
      },
    },
    defaultVariants: {'urgency': 'neutral'},
  );
}

/// The leading icon's className, sized to sit on the 12px label baseline.
WindRecipe expiryBadgeIconRecipe() {
  return const WindRecipe(base: 'size-3');
}
