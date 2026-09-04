import 'package:flutter/widgets.dart';

import '../app/models/shelf_read.dart';
import '../resources/views/products/shelf_photo_view.dart';
import 'preview_mock_harness.dart';
import 'responsive_screen_preview.dart';

/// Feature-screen preview: the read failed and the photograph is still here.
///
/// `ai-design.md` requires a failed capture to leave a resumable record rather than an orphaned
/// file, which is exactly what the MVP got wrong: it stored the upload before validating the
/// extraction, so a failure left a file with nothing pointing at it and a user who had to start
/// over.
///
/// So the picture stays, the callout says what was kept AND that no credit was spent, and the two
/// ways forward are both offered. Nothing is thrown away on the user's behalf.
class ShelfPhotoFailedScreenPreview extends StatelessWidget {
  /// Creates the failed-read shelf photo preview.
  const ShelfPhotoFailedScreenPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const ResponsiveScreenPreview(state: PreviewState.success, builder: _build);
  }

  static Widget _build(BuildContext context) => ShelfPhotoView.preview(ShelfRead(id: 'shelf-1'), previewState: ShelfReadState.failed);
}
