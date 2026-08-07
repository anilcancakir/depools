import 'package:magic/magic.dart';

/// Builds the [WindSlotRecipe] for the OptionRow component.
///
/// **The fill is the CARD tone, not the input tone, and that was a measured mistake.**
/// An earlier version used `bg-surface-container-high`, which DESIGN.md defines as the
/// input background. In dark mode it sits at `#2C2C2E` on a `#1C1C1E` sheet, reads as
/// raised, and therefore as tappable. In light mode the same token is `#E5E5EA` on a
/// `#FFFFFF` sheet: darker than its container, which in light mode reads as recessed and
/// inert. Anılcan called it immediately, in one glance at a light-mode screenshot: the
/// options looked disabled.
///
/// The root cause generalises beyond this component. **Elevation direction flips between
/// appearances**: raised means lighter in dark and whiter in light, so no single fill token
/// can carry "interactive" in both. A BORDER can, because a hairline reads as a discrete
/// control region either way. So the fill now matches the sheet (`surface-container`) and
/// the border does the work of saying this is a thing you press.
///
/// **Selection is not carried by colour alone.** DESIGN.md requires it of status and the
/// same logic applies to state: white against `#E3ECFF` is a subtle difference in light
/// mode and invisible to a colour-blind user, so the selected row also fills its radio.
/// That is the signal that survives both appearances and both kinds of eye.
///
/// The touch target comes from PADDING, never `min-h-11`. Measured: min-height grows the
/// box downward WITHOUT re-centring its content, landing 8.5px off centre on a 2x
/// screenshot, while padding grows symmetrically and stays centred.
WindSlotRecipe optionRowRecipe() {
  return const WindSlotRecipe(
    slots: {
      'root':
          'flex flex-row items-center gap-3 px-3 py-2.5 rounded-md '
          'bg-surface-container border border-color-border',
      'radio':
          'size-5 shrink-0 rounded-full border-2 border-color-border '
          'flex items-center justify-center',
      'dot': 'size-2.5 rounded-full',
      'body': 'flex flex-col gap-0.5 flex-1 min-w-0',
      'label': 'text-sm text-fg truncate',
      // Suggestions take the `ai` tone everywhere in this app: it is what the app inferred
      // rather than what the user chose, and DESIGN.md reserves a status family for the
      // state it names rather than for any tinted hint.
      'reason': 'text-xs text-ai truncate',
      'trailing': 'axis-min',
    },
    variants: {
      // A serial number is matched character by character against the object in the
      // user's hand, so it cannot render proportionally. Same reason barcodes and
      // quantities are mono everywhere else in this app.
      'type': {
        'text': {},
        'mono': {'label': 'font-mono text-sm text-fg truncate'},
      },
      'state': {
        'idle': {},
        'selected': {
          'root':
              'flex flex-row items-center gap-3 px-3 py-2.5 rounded-md '
              'bg-primary-container border border-color-border',
          'dot': 'size-2.5 rounded-full bg-primary',
        },
      },
    },
    defaultVariants: {'type': 'text', 'state': 'idle'},
  );
}
