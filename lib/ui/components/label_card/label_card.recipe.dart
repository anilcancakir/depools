import 'package:magic/magic.dart';

/// Builds the [WindSlotRecipe] for the LabelCard component.
///
/// Ink on paper, fixed in both appearances, from `depools_paper_tokens.dart`. The reason
/// lives there: this is a picture of a printed sheet, and a printed sheet is white at two
/// in the morning too.
///
/// **The overflow slot is the point of the whole component.** `labeling-and-printing.md`
/// requires that a layout which does not fit "say which field will not fit rather than
/// silently truncating", so a field that overruns its label renders in the `expired` tone
/// with its own line rather than being cut off at the edge. Truncation would hide exactly
/// the fact the user needs before spending a sheet of labels.
///
/// Two sizes rather than a continuous scale: `md` is the readable proof beside the sheet,
/// `sm` is the same content in a tighter box for a small stock label. The sheet itself
/// does NOT use this component; at sheet scale text is six pixels and [LabelPreview] draws
/// bars instead.
WindSlotRecipe labelCardRecipe() {
  return const WindSlotRecipe(
    slots: {
      'root':
          'flex flex-col justify-between gap-2 bg-paper rounded-sm border border-color-border p-3',
      'head': 'flex flex-col gap-0.5',
      'name': 'text-sm font-semibold text-ink',
      'meta': 'text-xs text-ink-muted truncate',
      // Height only, NO flex tokens. The bars are raw `Expanded` widgets and they have to
      // sit in a plain Flutter Row: wind's own flex box does not hand a bare Expanded the
      // parent it needs, and the failure is a RenderBox-was-not-laid-out assertion rather
      // than anything that names the cause.
      'bars': 'h-8',
      'bar': 'bg-ink',
      // The Row stretches its children vertically, so a bar needs no height of its own.
      'code': 'font-mono text-xs text-ink text-center tracking-wide',
      'overflow': 'text-xs font-medium text-expired',
    },
    variants: {
      'size': {
        'sm': {'name': 'text-xs font-semibold text-ink', 'bars': 'h-5'},
        'md': {},
      },
    },
    defaultVariants: {'size': 'md'},
  );
}
