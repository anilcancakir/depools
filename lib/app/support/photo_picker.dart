import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:magic/magic.dart';

/// Ask the user for a photograph, with the camera where there is one.
///
/// **The one place this app asks what kind of device it is on.** `DESIGN.md` forbids branching the
/// widget tree per platform and allows exactly this: the feature is present on all three and only
/// the INSTRUMENT differs. A phone photographs the thing in your hand; every other platform gets its
/// file dialog, which is what `image_picker` falls back to there anyway.
///
/// ### Why this is shared rather than a method on each screen
///
/// Three screens ask for a photograph: a receipt from the dashboard, a gallery picture from the
/// product screen, and a product to recognise from the scan screen. The first two each carried their
/// own copy of this, identical down to the numbers, and the third was about to be a fourth. The
/// numbers are the reason it matters rather than the duplication: they are a contract with the
/// server, and a copy that drifts to 4096 sends a photograph the upload rules refuse.
Future<XFile?> pickPhoto() {
  final ImagePicker picker = ImagePicker();
  final bool handheld = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  return picker.pickImage(
    source: handheld ? ImageSource.camera : ImageSource.gallery,
    // **Capped on the way IN, so a 12 megapixel photograph is not carried over a phone connection to
    // be refused by the server's own limit.** The server re-encodes what it reads, and it bounds the
    // long edge at the same 2048: two bounds that agree on purpose, so a client upload is re-encoded
    // but not resized and the model cannot be handed a visibly different picture depending on which
    // path it arrived by.
    maxWidth: 2048,
    maxHeight: 2048,
    imageQuality: 85,
  );
}
