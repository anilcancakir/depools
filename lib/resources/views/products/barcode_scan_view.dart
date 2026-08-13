import 'dart:async';

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart'
    show MSPageScaffold, MSButton, ButtonIntent, MSEmptyState, MSInput;

import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../app/controllers/scan_controller.dart';
import '../../../app/support/barcode_symbology.dart';
import '../../../app/support/scan_presence.dart';
import '../../../app/models/scan_entry.dart';
import '../../../ui/components/scan_row/scan_row.dart';
import '../../../ui/components/section_card/section_card.dart';

/// Continuous barcode scanning, and the batch it accumulates.
///
/// **The camera never closes, so this cannot be a result screen.**
/// `barcode-and-catalog.md`'s third acceptance criterion is explicit: twenty items produce
/// twenty resolutions without closing the camera between them. That single line disqualifies
/// the obvious design, which is a modal per scan showing what was found. Unpacking a
/// delivery means scanning while both hands are busy, and a dialog that has to be dismissed
/// twenty times is a dialog that gets dismissed without being read.
///
/// So the scan result is a QUEUE that grows beside a live viewfinder, and confirmation
/// happens once for the whole batch.
///
/// ### What each row can be
///
/// Five sources, from `ScanSource`, and only one of them asks for anything. The other four
/// will be written as they stand: a product the tenant already owns, a catalog hit, an
/// unverified hit, or the user's own past manual entry replayed. Provenance is printed only
/// when the answer is not the tenant's own inventory, which is this screen's answer to the
/// open question `barcode-and-catalog.md` raised about showing provenance without a source
/// label on every row.
///
/// ### One destination for the batch, and why that is not a shortcut
///
/// A mixed delivery genuinely does go to different shelves, so a single destination looks
/// like an oversimplification. It is not, because receiving and putting away are two
/// events: everything lands where it was received, and moving it onward is exactly what the
/// move sheet exists for (D38). Asking for a per-row destination here would ask the user to
/// decide, at the bench with a box in their hands, something they will only know once they
/// are standing at the shelf.
///
/// ### The layout swaps by WIDTH, not by platform
///
/// One app, one feature set, both input paths available everywhere. What changes with width
/// is which one leads. At phone width the viewfinder leads, because the phone IS the
/// scanner and it is already pointed at a label. At desktop width the digit field leads,
/// because a desktop barcode reader is an HID keyboard that types digits and presses enter,
/// while a laptop webcam points at the operator's face. Same widgets, `lg:order-first`.
/// ### The fixture is REPLACED, not shadowed
///
/// `flutter-app.md` is explicit that a screen reading both a fixture and an endpoint diverges the
/// moment the API changes, so `scanBatch` is gone from this file rather than kept behind a flag. The
/// two constructors it fed are gone with it: "has scans" is now a fact about the batch rather than a
/// variant chosen at construction, and the empty state is what the controller publishes before the
/// first read.
@immutable
class BarcodeScanView extends StatefulWidget {

  /// Creates the [BarcodeScanView].
  const BarcodeScanView({super.key});

  @override
  State<BarcodeScanView> createState() => _BarcodeScanViewState();
}

class _BarcodeScanViewState extends State<BarcodeScanView> {
  /// Off and on are two glyphs, because a torch button that never changes gives no feedback for
  /// the one action on this screen whose effect is outside the app's own pixels.
  static const IconData _torchIcon = Icons.flashlight_off_outlined;
  static const IconData _torchOnIcon = Icons.flashlight_on_outlined;
  static const IconData _cameraIcon = Icons.qr_code_scanner_outlined;
  static const IconData _emptyIcon = Icons.inventory_2_outlined;
  static const IconData _photoIcon = Icons.photo_camera_outlined;
  static const IconData _shelfIcon = Icons.grid_view_outlined;

  /// The batch destination: the last location used for receiving.
  ///
  /// **Not category affinity, and that is a deliberate departure** from every other
  /// location suggestion in the app. Affinity answers "where does this CATEGORY go", which
  /// is exactly the question a mixed batch cannot ask: milk and a screwdriver set disagree,
  /// and picking one row's winner for the whole batch would be arbitrary dressed up as
  /// intelligence. Receiving location is a habit rather than a per-product fact, so the last
  /// one used is both the better guess and an honest one.
  static const String _destination = 'Depo › Raf A';

  /// Whether a read is a new carton or the same one still in view.
  ///
  /// **This replaced `detectionTimeoutMs`, and the reason came from a real scan.** That parameter is
  /// a TIMER: it suppresses a repeat for a fixed period, so a label held steady in front of the lens
  /// produced one read per period and one carton counted twice. On a screen whose camera never
  /// closes, "held for three seconds" is the ordinary case, so any timer long enough to stop it is
  /// also long enough to swallow a real second carton. [ScanPresence] counts EDGES instead.
  final ScanPresence _presence = ScanPresence();

  /// Every format the platform can read, which is the package's own default.
  ///
  /// **No `formats:` argument, deliberately.** Passing `const <BarcodeFormat>[]` says the same thing
  /// (`mobile_scanner`'s own doc comment: "If this is empty, all supported formats are detected")
  /// and reads like the opposite. Narrowing would be wrong here anyway: a delivery carries EAN-13 on
  /// the groceries, Code128 on a supplier's own repacks and the occasional QR, and a receiving bench
  /// cannot know which is in the next box.
  /// **No `detectionTimeoutMs`, deliberately.** The gate above needs to SEE every frame a code is
  /// in, because a sighting that never arrives looks like the label having left. Suppressing reads
  /// in the package would blind the thing that decides.
  late final MobileScannerController _scanner = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
  );

  final ScanController _controller = ScanController.instance;
  final TextEditingController _manual = TextEditingController();

  /// Whether the torch is on, so the button can say which way it will move.
  bool _torchOn = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _manual.dispose();
    // The camera is a platform resource and this screen is the only thing holding it. A route
    // popped without releasing it leaves the light on, literally, on a phone.
    _scanner.dispose();
    super.dispose();
  }

  /// One capture from the camera, which may hold several labels.
  ///
  /// **Every barcode in the frame is offered to the gate, not just the first.** A receiving bench
  /// can have two labels in view at once, and taking `first` would make which one counts depend on
  /// the decoder's ordering. The gate is per code, so both can be new and neither suppresses the
  /// other.
  Future<void> _onDetect(BarcodeCapture capture) async {
    final DateTime now = DateTime.now();

    for (final Barcode read in capture.barcodes) {
      final String? value = read.rawValue;

      if (value == null || value.isEmpty) continue;

      if (!_presence.shouldCount(value, now)) continue;

      await _controller.scan(value, symbology: symbologyOf(read.format));
    }

    _presence.prune(now);
  }

  Future<void> _toggleTorch() async {
    await _scanner.toggleTorch();

    if (mounted) setState(() => _torchOn = !_torchOn);
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  /// The batch, from the controller rather than from a fixture.
  List<ScanEntry> get _scans => _controller.entries;

  /// Rows that will be written as they stand.
  List<ScanEntry> get _settled => _scans.where((ScanEntry e) => e.isSettled).toList();

  bool get hasScans => _controller.hasScans;

  /// Reads whatever the user typed, then clears the field for the next one.
  ///
  /// **Cleared after the call is dispatched, not after it returns.** A receiving bench types the
  /// next code while the last one is still resolving, and a field that clears late eats the first
  /// digits of the next read.
  void _submitManual() {
    final String code = _manual.text.trim();

    if (code.isEmpty) return;

    _manual.clear();
    unawaited(_controller.scan(code));
  }


  @override
  Widget build(BuildContext context) {
    return MSPageScaffold(
      title: Lang.get('screens.scan.title'),
      subtitle: hasScans
          ? Lang.get('screens.scan.subtitle', {'scans': _scans.length, 'ready': _settled.length})
          : Lang.get('screens.scan.subtitle_empty'),
      children: [
        // items-start so the capture column keeps its own height at lg instead of
        // stretching to match a queue that can be twenty rows long.
        WDiv(
          className: 'flex flex-col lg:flex-row items-start gap-4',
          children: [_buildCapture(), _buildBatch()],
        ),
      ],
    );
  }

  /// The two ways a barcode gets in: the camera, and typed digits.
  Widget _buildCapture() {
    return WDiv(
      className: 'flex flex-col gap-4 w-full lg:flex-1',
      children: [_buildViewfinder(), _buildCameraHint(), _buildManualEntry()],
    );
  }

  /// What to do with the camera, on a surface the app controls.
  ///
  /// **Under the panel rather than over it.** It sat centred on the feed and was unreadable the
  /// moment the feed was bright, which is the same problem D65 solved for the framing strokes and
  /// did not solve for copy: a stroke can be a contrasting PAIR, a sentence cannot. Overlaying it
  /// with a scrim wide enough to carry it would cover the thing the user is aiming.
  ///
  /// Nominal, and it does NOT promise that only what is inside the frame counts: `scanWindow` is
  /// unsupported on web, so the decoder reads the whole frame on every platform and the rectangle is
  /// an aiming aid.
  Widget _buildCameraHint() {
    return WText(
      Lang.get('screens.scan.camera_hint'),
      className: 'text-xs text-fg-muted text-center',
    );
  }

  /// The live camera area.
  ///
  /// **The preview FILLS the panel, and it used to sit in a 128px box in the middle of it.** That
  /// was defensible while the box held a placeholder glyph and stopped being defensible the moment a
  /// camera painted there: a viewfinder the size of a postage stamp cannot be aimed, and Anılcan
  /// called it the moment he saw it on screen. The frame is now an overlay on top of a full-bleed
  /// feed, which is what every scanner interface does and for the same reason.
  ///
  /// **The frame is LANDSCAPE, not square.** An EAN-13 is roughly twice as wide as it is tall, so a
  /// square aiming rectangle invites the user to centre a wide label inside the wrong shape and then
  /// hold the phone closer than it needs to be. The old square was a consequence of the placeholder
  /// glyph being square.
  ///
  /// It is drawn with the same two-stroke pair the shelf-photo boxes use (D65), and here the reason
  /// is no longer hypothetical: the background is a live camera feed, so a single hairline picked
  /// against a dark panel would vanish over a bright shelf. The better of the two strokes clears
  /// 3.91:1 over any background that can exist.
  ///
  /// **Three layers, because wind turns a container with a positioned child into a Stack** and a
  /// Stack ignores `items-center justify-center`. So the centring lives INSIDE the overlay layer
  /// rather than on the box that holds it, which is the same trap this file already hit once with
  /// the torch.
  Widget _buildViewfinder() {
    return WDiv(
      className: 'relative w-full',
      children: [
        // Layer 1: the feed. `overflow-hidden` is what keeps it inside the radius instead of
        // squaring off the corners.
        WDiv(
          // **Paint-only tokens, no flex.** `MobileScanner` carries a `LayoutBuilder` that wants to
          // fill its box, and a wind `flex` WDiv around it produces `RenderBox was not laid out` on
          // the internal `_RenderLayoutBuilder`: twelve of them per paint, invisible in a screenshot
          // that looked correct. The anti-pattern table names this exactly ("let one layer own the
          // main axis"), and the centring the error state needs is a plain `Center` below.
          className: 'w-full h-56 md:h-64 rounded-lg overflow-hidden bg-surface-container-high',
          child: MobileScanner(
            controller: _scanner,
            onDetect: _onDetect,
            // **The state a user cannot act on unless told.** A refused permission or a machine
            // with no camera has to read as "type it instead", which the field beside this already
            // offers, rather than as a black rectangle that looks like it is working. Web asks for
            // permission per origin, so this is the ordinary first-run state there, not an edge.
            errorBuilder: (BuildContext context, MobileScannerException error) => Center(
              child: WDiv(
                className: 'flex flex-col items-center justify-center gap-2 p-4',
                children: [
                  const WIcon(_cameraIcon, className: 'size-8 text-fg-disabled'),
                  WText(
                    Lang.get('screens.scan.camera_unavailable'),
                    className: 'text-xs text-fg-muted text-center',
                  ),
                ],
              ),
            ),
          ),
        ),
        // Layer 2: the aiming frame, centred over the feed. `IgnorePointer` because it is paint
        // rather than a control: without it this box would swallow a tap meant for the torch.
        WDiv(
          // **`inset-0` is what gives this layer its size, and `h-full` is what broke it.** Wind
          // asserts by name on `h-full` inside a vertical scroll, and the app shell wraps every
          // route in one: the whole panel rendered as a red assertion box. The flex classes belong
          // on THIS box rather than a nested one, because the Stack is the parent above.
          className: 'absolute inset-0 flex flex-col items-center justify-center gap-3',
          children: [
            // `IgnorePointer` because both of these are paint rather than controls: without it this
            // layer swallows the tap meant for the torch behind it.
            IgnorePointer(
              child: WDiv(
                className: 'rounded-md border-2 border-color-overlay-ink',
                child: const WDiv(
                  className: 'w-48 h-24 rounded-md border-2 border-color-overlay-paper',
                ),
              ),
            ),
          ],
        ),
        // Layer 3: the torch. Not a nicety here: half of all stock lives in a cupboard, a cellar or
        // the back of a van, and a scanner that cannot light its own target fails there.
        WDiv(
          // **A scrim, because a ghost control over a photograph has no contrast to rely on.** The
          // frame beside it is protected by the two-stroke pair (D65); a glyph cannot be, so it sits
          // on a background the app owns.
          //
          // The surface family rather than the overlay one, and that was a correction: `bg-ink` with
          // `text-paper` reads well and `text-paper` DOES NOT EXIST. Wind drops an unknown alias
          // silently, so the glyph would have rendered at full foreground brightness, which is black
          // in light mode on a black scrim. `bg-surface-container` with `text-fg` is legible in both
          // appearances by construction, because both sides come from the same appearance.
          className: 'absolute top-2 right-2 rounded-lg bg-surface-container',
          child: MSButton(
            onPressed: _toggleTorch,
            intent: ButtonIntent.ghost,
            className: 'min-h-11 min-w-11 justify-center',
            // **The label says what the button will DO, not what the torch currently is.** A screen
            // reader user pressing "Torch on" and hearing nothing change would have no way to tell
            // whether the press landed, and the glyph is the only other signal.
            semanticLabel: Lang.get(_torchOn ? 'screens.scan.torch_off' : 'screens.scan.torch_on'),
            child: WIcon(
              _torchOn ? _torchOnIcon : _torchIcon,
              className: _torchOn ? 'size-5 text-fg' : 'size-5 text-fg-muted',
            ),
          ),
        ),
      ],
    );
  }

  /// Typed digits, for a damaged label or a desktop barcode gun.
  ///
  /// `lg:order-first` is the whole width rule in one token: at desktop width this field is
  /// the primary input because a hardware reader types into it, and at phone width it sits
  /// under the viewfinder where it belongs.
  Widget _buildManualEntry() {
    return WDiv(
      className: 'w-full lg:order-first',
      child: SectionCard(
        label: Lang.get('screens.scan.barcode'),
        children: [
          // **Both halves are sized by PADDING, and `h-11` on the field is what broke it.**
          // `design.md` names this for MSButton ("min-height grows the box downward without
          // re-centring the label") and it is just as true of MSInput: with `h-11` the placeholder
          // and the caret measured 6 logical px above the button's label in the same row. Anılcan
          // caught it on screen; `items-center` did not fix it, which the same measurement showed.
          //
          // The second half is a wind trap worth knowing. `MSInput`'s recipe declares NO padding of
          // its own, so a bare `py-3.5` in the caller's className replaces the whole inset rather
          // than the vertical part: the left gap went from 12 logical px to zero and the text sat
          // against the border. Both axes have to be written together.
          WDiv(
            className: 'flex flex-row items-center gap-2',
            children: [
              WDiv(
                className: 'flex-1 min-w-0',
                child: MSInput(
                  className: 'bg-surface-container px-3 py-3.5',
                  placeholder: '13 hane',
                  type: InputType.number,
                  controller: _manual,
                  // Kept, because a desktop barcode reader is an HID keyboard that types digits and
                  // presses enter, and that is the path this field was designed for.
                  onSubmitted: (_) => _submitManual(),
                ),
              ),
              // **Added because the field had no other way to be submitted.** On a phone the
              // keyboard's own action fires `onSubmitted`; at desktop width, where this column
              // LEADS by design, a person typing with a mouse in their hand had nothing to press.
              // Found by driving the screen rather than by reading it.
              MSButton(
                onPressed: _submitManual,
                intent: ButtonIntent.secondary,
                className: 'shrink-0 px-4 py-3 justify-center',
                child: WText(Lang.get('screens.scan.add')),
              ),
            ],
          ),
          // Checksum validation is the reason this field is not just a shortcut: a
          // mistyped EAN-13 is caught here rather than becoming a product nobody can
          // scan again.
          WText(Lang.get('screens.scan.checksum'), className: 'text-xs text-fg-muted'),
        ],
      ),
    );
  }

  /// The accumulating batch, plus what committing it will do.
  Widget _buildBatch() {
    return WDiv(
      className: 'flex flex-col gap-4 w-full lg:flex-1',
      children: [
        hasScans ? _buildQueue() : _buildEmptyQueue(),
        _buildCommit(),
        // Both camera paths stay available whatever the queue holds: the user who needs them
        // is the one holding an unreadable label, and that is not a state the app can detect
        // in order to offer the button at the right moment.
        if (hasScans) _buildPhotoPaths(),
      ],
    );
  }

  /// The queue itself, newest first.
  Widget _buildQueue() {
    return SectionCard(
      label: Lang.get('screens.scan.scanned_group'),
      count: Lang.get('screens.scan.scan_count', {'count': _scans.length}),
      children: [
        for (final ScanEntry scan in _scans)
          ScanRow(
            barcode: scan.barcode,
            productName: scan.productName,
            source: scan.source,
            count: scan.count,
            unit: scan.unit,
            // **No on-hand figure on a live row, and its absence is a decision.** The fixture
            // carried one because it could invent it. The resolve endpoint answers what a code IS
            // and deliberately not what the tenant holds, so printing a stock figure here would
            // need a second request per scanned row, at a bench, while the camera is running.
            onHandFormatted: null,
            // Stage 6 of the cascade found nothing anywhere, and typing or photographing the
            // product is the only way forward. That is exactly what `ProductDraftView` is,
            // and it had no entry point until now. A settled row goes nowhere yet.
            onTap: scan.source == ScanSource.unmatched
                ? () => MagicRoute.to('/draft')
                : () {},
          ),
      ],
    );
  }

  /// The queue before the first read.
  Widget _buildEmptyQueue() {
    return SectionCard(
      label: Lang.get('screens.scan.scanned_group'),
      children: [
        WDiv(
          // Full width so MSEmptyState's own `items-center` has something to centre in.
          className: 'w-full',
          child: MSEmptyState(
            icon: _emptyIcon,
            title: Lang.get('screens.scan.empty_title'),
            description:
                Lang.get('screens.scan.empty_description'),
          ),
        ),
      ],
    );
  }

  /// The destination and the commit pair.
  ///
  /// **Absent entirely before the first read**, rather than showing a destination and a
  /// zero count. A commit bar reading "0 ürünü ekle" next to an empty queue is a button
  /// that cannot work, and the disabled look it would need does not visibly exist on a
  /// primary MSButton in this theme. Nothing to commit, nothing to place: only the photo
  /// fallback stays, because that is the one path still open.
  Widget _buildCommit() {
    if (!hasScans) {
      return _buildPhotoPaths();
    }

    final int ready = _settled.length;
    final int unmatched = _controller.unmatchedCount;

    return WDiv(
      className: 'flex flex-col gap-2 pb-2',
      children: [
        SectionCard(
          label: Lang.get('screens.scan.where_group'),
          children: [
            WDiv(
              className: 'flex flex-row items-center justify-between gap-3 py-1',
              children: [
                WText(_destination, className: 'text-sm text-fg flex-auto min-w-0'),
                MSButton(
                  onPressed: () {},
                  intent: ButtonIntent.ghost,
                  className: 'justify-center',
                  child: WText(Lang.get('screens.scan.change')),
                ),
              ],
            ),
            WText(
              Lang.get('screens.scan.where_note'),
              className: 'text-xs text-fg-muted',
            ),
          ],
        ),
        // Products, never a quantity sum. The rows can be in different units, and adding
        // three kilos to four items produces a number that means nothing.
        WText(
          unmatched == 0
              ? Lang.get('screens.scan.will_write', {'count': ready})
              : Lang.get('screens.scan.will_write_partial', {'count': ready, 'unmatched': unmatched}),
          className: 'text-sm text-fg-muted',
        ),
        MSButton(
          onPressed: () {},
          fullWidth: true,
          className: 'justify-center',
          child: WText(Lang.get('screens.scan.submit', {'count': ready})),
        ),
      ],
    );
  }

  /// The two camera paths that are not barcode reading, and what each one yields.
  ///
  /// **They are different features and were one button until Anılcan asked what it was for.**
  /// `Fotoğraftan tanıt` is single-product recognition: point at one thing, get one draft card.
  /// `Rafı tara` is the shelf case: point at a shelf, get a numbered region per product and a
  /// bulk accept. Same camera, same credit price, completely different output, so they cannot
  /// share a label.
  ///
  /// They live here because this is the camera screen. A user already holding the phone up to a
  /// shelf should not have to go back to a list to find the shelf reader, and criterion 2 wants
  /// the single-product path reachable from a barcode that missed.
  ///
  /// Each line says what comes back, because "recognise from a photo" does not tell you whether
  /// you are about to review one card or six.
  Widget _buildPhotoPaths() {
    return SectionCard(
      label: Lang.get('screens.scan.other_ways'),
      children: [
        _photoPath(
          _photoIcon,
          Lang.get('screens.scan.from_photo'),
          Lang.get('screens.scan.from_photo_note'),
          Lang.get('screens.scan.from_photo_label'),
        ),
        _photoPath(
          _shelfIcon,
          Lang.get('screens.scan.shelf'),
          Lang.get('screens.scan.shelf_note'),
          Lang.get('screens.scan.shelf_label'),
        ),
      ],
    );
  }

  /// One path: what it is called, and what it gives back.
  Widget _photoPath(IconData icon, String label, String yields, String semanticLabel) {
    return WAnchor(
      onTap: () {},
      semanticLabel: semanticLabel,
      child: WDiv(
        className:
            'flex flex-row items-center gap-3 px-3 py-3 rounded-md bg-surface-container border border-color-border',
        children: [
          WDiv(
            className: 'size-5 shrink-0 flex items-center justify-center',
            child: WIcon(icon, className: 'size-5 text-fg'),
          ),
          WDiv(
            className: 'flex flex-col gap-0.5 flex-1 min-w-0',
            children: [
              WText(label, className: 'text-sm font-medium text-fg'),
              WText(yields, className: 'text-xs text-fg-muted'),
            ],
          ),
        ],
      ),
    );
  }
}
