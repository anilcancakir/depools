import 'package:magic/magic.dart';

/// Builds the [WindSlotRecipe] for the ScanRow component.
///
/// **Deliberately not ReceiptLineRow, though the two rows look almost identical.** That
/// component's states are `receipt_lines.resolution_state` verbatim, and its own docblock
/// says why: naming them anything else would need a translation layer at the API
/// boundary, which is the mistake the stock-out reason enum already made once. A scan
/// carries PROVENANCE (which stage of the resolution cascade answered), not a receipt
/// line's resolution state, so folding scans into that enum would corrupt the one thing
/// it is careful about. Two small rows with honest domain enums beat one row with a
/// union enum, and extracting a shared base for two callers would be the abstraction the
/// rules already tell us to wait on.
///
/// Three looks carry five states, and the axis is the ICON TONE rather than the row: what
/// varies between a settled scan and one needing the user is how hard the leading glyph
/// pulls, not the row's geometry.
///
/// `settled` covers every row that will be written as it stands. The difference between
/// "already in your inventory" and "will be created" lives in the meta line, because a
/// user scanning a delivery cares whether a row needs them, not which stage of the
/// cascade answered it.
///
/// `attention` is the one row that pulls the eye, and it takes the `ai` tone for the same
/// reason `DraftField` does: the app worked as far as it could and the rest is yours.
///
/// `unverified` sits between them. It will be written, so it is not attention, but it
/// came from a source `barcode-and-catalog.md` requires be presented as unverified, so it
/// is not silent either.
WindSlotRecipe scanRowRecipe() {
  return const WindSlotRecipe(
    slots: {
      'root': 'flex flex-row items-start gap-3 py-2',
      'iconBox': 'size-4 shrink-0 flex items-center justify-center',
      'icon': 'size-4',
      'body': 'flex flex-col gap-0.5 flex-1 min-w-0',
      'name': 'text-sm font-semibold text-fg truncate',
      // The barcode is machine text the user checks digit by digit against the label in
      // their hand, so it is mono wherever it appears, exactly like the receipt's
      // extracted string.
      'barcode': 'font-mono text-xs text-fg-muted truncate',
      'unmatchedBarcode': 'font-mono text-sm font-semibold text-fg truncate',
      'prompt': 'text-sm font-medium text-ai',
      'meta': 'text-xs text-fg-muted truncate',
      'trailing': 'flex flex-col items-end gap-0.5 axis-min',
    },
    variants: {
      'state': {
        'settled': {'icon': 'text-fg-disabled'},
        'unverified': {'icon': 'text-fg-muted'},
        'attention': {'icon': 'text-ai'},
      },
    },
    defaultVariants: {'state': 'settled'},
  );
}
