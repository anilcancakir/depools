// SerialRow component folder-local barrel.
//
// Re-exports the public surface (component + recipe). The preview is
// intentionally NOT re-exported: `previews:refresh` discovers `*.preview.dart`
// files directly and the preview must stay out of the release barrel.

export 'serial_row.dart';
export 'serial_row.recipe.dart';
