import 'package:flutter/widgets.dart';

import '../resources/views/products/shelf_photo_view.dart';
import 'preview_mock_harness.dart';
import 'screen_preview_scaffold.dart';

/// Feature-screen preview: the photograph still being read.
///
/// **The state the MVP got worst.** It showed a blank screen through a two-minute image
/// analysis, so this shows the photograph immediately, draws each box as its region is
/// finished, counts how far it has got, and leaves a skeleton row where the next candidate
/// will land.
///
/// The point of the skeleton is that a list which stops at four looks finished at four. Latency
/// that is visible is latency a user will wait through; latency that looks like completion is
/// what makes them navigate away and file a bug.
class ShelfPhotoReadingScreenPreview extends StatelessWidget {
  /// Creates the mid-read shelf photo preview.
  const ShelfPhotoReadingScreenPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const ScreenPreviewScaffold(state: PreviewState.success, builder: _build);
  }

  static Widget _build(BuildContext context) => const ShelfPhotoView.reading();
}
