import 'package:magic/magic.dart';

/// Builds the [WindSlotRecipe] for the OptionRow component.
///
/// **Every option carries a fill, selected or not.** A group where only the chosen row has
/// a background reads as one highlight among labels rather than a set of choices, which is
/// a correction Anılcan made on the stock sheets and which this component now enforces in
/// one place instead of four.
///
/// The touch target comes from PADDING, never `min-h-11`. Measured: min-height grows the
/// box downward WITHOUT re-centring its content, landing 8.5px off centre on a 2x
/// screenshot, while padding grows symmetrically and stays centred.
///
/// `bg-surface-container-high` is the same tone the search field uses for "this is an
/// input", which is the right family of signal for "this is pickable".
///
/// The selected state adds a border on top of the tinted fill, so selection survives for a
/// user who cannot separate the two container tones.
WindSlotRecipe optionRowRecipe() {
  return const WindSlotRecipe(
    slots: {
      'root': 'flex flex-row items-center gap-3 px-3 py-2.5 rounded-md bg-surface-container-high',
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
        },
      },
    },
    defaultVariants: {'type': 'text', 'state': 'idle'},
  );
}
