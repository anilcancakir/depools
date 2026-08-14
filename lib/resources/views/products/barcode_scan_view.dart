import 'dart:async';

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart'
    show
        MSPageScaffold,
        MSButton,
        ButtonIntent,
        MSEmptyState,
        MSInput,
        MSBottomSheet;

import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../app/controllers/scan_controller.dart';
import '../../../app/support/barcode_symbology.dart';
import '../../../app/support/plural.dart';
import '../../../app/support/scan_presence.dart';
import '../../../app/models/scan_entry.dart';
import '../../../ui/components/scan_row/scan_row.dart';
import '../../../ui/components/section_card/section_card.dart';
import 'destination_sheet.dart';
import 'scan_draft_sheet.dart';

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

  /// The width at which both capture paths fit side by side.
  ///
  /// Wind's own `lg`, and the same 1024 the app shell swaps its tree at. In Dart rather than as a
  /// `lg:` prefix because the decision here is not only which widget is drawn: the camera is a
  /// platform resource that has to be stopped and started, and no className can express that.
  static const double _bothFitWidth = 1024;

  /// Whether the torch is on, so the button can say which way it will move.
  bool _torchOn = false;

  /// Whether the digit field has the phone's screen instead of the viewfinder.
  ///
  /// **Only meaningful below [_bothFitWidth], and it is a height budget rather than a preference.**
  /// DESIGN.md's own rule is that a screen operated WHILE typing is laid out against what the keyboard
  /// leaves, not against the viewport, and this screen had the camera and the field stacked above a
  /// queue that grows without bound: the viewfinder got a fraction of the height, and raising the
  /// keyboard to use the field covered the queue the field feeds.
  ///
  /// At desktop width neither is the fallback, so both stay: a hardware barcode reader is an HID
  /// keyboard typing into the field, while a laptop webcam points at the operator's face.
  bool _typing = false;

  /// The destination's own path, for the row that says where the batch will land.
  ///
  /// Presentation, held here rather than on the controller: the controller owns the location's ID,
  /// which is what the write needs.
  String? _destinationPath;

  /// The tenant's locations, for the picker.
  List<DestinationOption> _locations = const <DestinationOption>[];

  /// The recent destinations, newest first, from the ledger.
  List<String> _recentIds = const <String>[];

  /// The server's refusal, when there was one.
  String? _error;

  /// Whether a draft sheet is open, so a scan landing behind it cannot stack a second one.
  bool _drafting = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
    // Asked once, when the screen opens. A receiving bench does not change shelves between boxes, so
    // re-asking per scan would be a request per carton for an answer that does not move.
    unawaited(_loadDestination());
  }

  /// Loads the locations and the shelves recent deliveries went to.
  Future<void> _loadDestination() async {
    await _controller.loadDestination();

    final dynamic response = await Http.get('/locations');

    if (!mounted || !response.successful) return;

    final dynamic rows = response['data'];

    if (rows is! List) return;

    setState(() {
      _locations = <DestinationOption>[
        for (final dynamic row in rows)
          if (row is Map && row['id'] is String)
            DestinationOption(
              id: row['id'] as String,
              name: (row['name'] as String?) ?? '',
              // `full_path` is the hierarchy the picker's description line shows; it falls back to
              // the name for a root, where there are no ancestors to print.
              fullPath: (row['full_path'] as String?) ?? (row['name'] as String?) ?? '',
              depth: (row['depth'] as num?)?.toInt() ?? 0,
              productCount: (row['stock_count'] as num?)?.toInt() ?? 0,
            ),
      ];
      _recentIds = _controller.recentDestinationIds;
      _destinationPath = _pathOf(_controller.destinationId);
    });
  }

  /// The path of a location id, or null when it names none of them.
  String? _pathOf(String? id) {
    if (id == null) return null;

    for (final DestinationOption option in _locations) {
      if (option.id == id) return option.fullPath;
    }

    return null;
  }

  /// Opens the shelf picker and moves the batch's destination to what it returns.
  ///
  /// The same shape the count screen's picker uses, including the `Builder`: without it the body is
  /// built from the VIEW's context, which resolves to the route BEHIND the sheet, and tapping an
  /// option pops the screen instead of the sheet.
  Future<void> _pickDestination() async {
    final String? current = _controller.destinationId;

    final String? picked = await MSBottomSheet.show<String>(
      context,
      title: Lang.get('screens.scan.pick_destination_title'),
      // The sheet is its own widget, so the search field's state belongs to it rather than to this
      // screen: a `setState` here while the sheet is open would rebuild the scan queue behind it.
      body: DestinationSheet(
        options: _locations,
        recentIds: _recentIds,
        selectedId: current,
      ),
    );

    if (picked == null || !mounted || picked == current) return;

    _controller.chooseDestination(picked);
    setState(() {
      _destinationPath = _pathOf(picked);
      // A destination the user just chose cannot still be the reason a write failed.
      _error = null;
    });
  }

  /// Writes the batch, keeping the server's own sentence when it refuses.
  ///
  /// **The rows are captured BEFORE the write, because the write consumes them.** A successful commit
  /// removes every settled row from the batch, so a toast built afterwards would have nothing left to
  /// count. The snapshot is exact rather than approximate: `commit()` filters the same set
  /// synchronously before its first `await`, so no scan can land between the two.
  Future<void> _commit() async {
    final List<ScanEntry> writing = _settled;
    final String? destination = _destinationPath;

    final String? failure = await _controller.commit();

    if (!mounted) return;

    setState(() => _error = failure);

    // A refusal is reported in place, under the button, because the server's sentence names the
    // reason and a toast would take it off screen after a few seconds.
    if (failure == null) {
      _reportWritten(writing, destination);
    }
  }

  /// Says what the commit wrote, which was previously the one outcome with no feedback at all.
  ///
  /// **A one-row batch names the product and its count**, because that is the case the screen is used
  /// for most: somebody scans one carton twice and the useful fact is the 2, not that "1 product" was
  /// added. Several rows can only be counted as products.
  ///
  /// **No unit total across rows, and that is the same decision the write summary records.** Rows can
  /// be in different units, so adding three kilos to four pieces produces a number that means
  /// nothing. `2 × Pınar Süt 1 L` carries the count without claiming a unit.
  void _reportWritten(List<ScanEntry> writing, String? destination) {
    if (writing.isEmpty) return;

    final String what = writing.length == 1
        ? Lang.get('screens.scan.added_one', {
            'count': writing.first.count,
            'product': writing.first.productName ?? writing.first.barcode,
          })
        : plural('screens.scan.added_many', writing.length, {'count': writing.length});

    MagicFeedback.success(
      Lang.get('screens.scan.added_title'),
      // The destination clause is dropped rather than faked when the locations list has not
      // answered: the batch still landed somewhere real, and naming the wrong shelf is worse than
      // naming none.
      destination == null
          ? Lang.get('screens.scan.added_plain', {'what': what})
          : Lang.get('screens.scan.added_to', {'what': what, 'location': destination}),
    );
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
  void _onDetect(BarcodeCapture capture) {
    final DateTime now = DateTime.now();

    for (final Barcode read in capture.barcodes) {
      final String? value = read.rawValue;

      if (value == null || value.isEmpty) continue;

      final String? symbology = symbologyOf(read.format);

      if (!_presence.shouldCount(value, symbology, now)) continue;

      // **Dispatched rather than awaited.** Awaiting made the second label in one capture wait for
      // the first one's lookup, so two labels in frame together resolved half a second apart while
      // the camera went on delivering frames. The controller already orders by scan sequence rather
      // than by arrival, which is what makes firing them together safe.
      unawaited(_scanThenPrompt(value, symbology));
    }

    _presence.prune(now);
  }

  Future<void> _toggleTorch() async {
    await _scanner.toggleTorch();

    if (mounted) setState(() => _torchOn = !_torchOn);
  }

  /// Scans, and opens the card for any read that is about to create a product.
  ///
  /// **Not only for a code that missed, and that is a correction.** The first version asked about an
  /// unmatched row alone, so a barcode only the SHARED CATALOGUE knew slid into the queue with a name
  /// nobody here had ever seen and became this tenant's own product on commit. A find is a claim about
  /// somebody else's data, so it gets one look before it is adopted.
  ///
  /// **A product the tenant already owns still opens nothing**, which is what keeps this from becoming
  /// the modal-per-read `barcode-and-catalog.md` rejects outright: unpacking twenty boxes of things
  /// already in inventory produces twenty silent rows. [ScanEntry.needsAsking] draws that line at the
  /// presence of a product id, and it draws the other one at [ScanEntry.asked]: the question is asked
  /// once per ROW, so the second carton of a confirmed find increments it in silence.
  ///
  /// The sheet is skipped when one is already open, because a second read while the user is typing
  /// would stack sheets over each other and the row behind the top one would be forgotten.
  Future<void> _scanThenPrompt(String code, String? symbology) async {
    await _controller.scan(code, symbology: symbology);

    if (!mounted || _drafting) return;

    // A plain loop rather than `firstWhereOrNull`, which needs `package:collection` and is not
    // already a dependency of this app: one import for one lookup is not the trade.
    ScanEntry? row;

    for (final ScanEntry entry in _controller.entries) {
      if (entry.barcode == code.trim() && entry.symbology == symbology) {
        row = entry;
        break;
      }
    }

    if (row == null || !row.needsAsking) return;

    _drafting = true;

    try {
      await _openDraft(row);
    } finally {
      _drafting = false;
    }
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  /// The batch, from the controller rather than from a fixture.
  List<ScanEntry> get _scans => _controller.entries;

  /// Rows that will be written as they stand.
  List<ScanEntry> get _settled => _scans.where((ScanEntry e) => e.isSettled).toList();

  bool get hasScans => _controller.hasScans;

  /// Opens the card for a row, prefilled with whatever the cascade found.
  ///
  /// **The title asks a different question depending on what came back**, because the two cases are
  /// genuinely different work. With a name on screen the answer is a yes or a correction, so the card
  /// asks whether it is right. With nothing, the user is the only source, so it asks what the thing is.
  /// One title covering both read as an interrogation of an answer the app had already found.
  ///
  /// Returns nothing: the row is updated through the controller, so the queue and the batch stay one
  /// source of truth even while a sheet is open above them.
  Future<void> _openDraft(ScanEntry entry) async {
    final bool found = entry.productName != null;

    final ScanDraft? draft = await MSBottomSheet.show<ScanDraft>(
      context,
      title: Lang.get(found ? 'screens.scan.confirm_title' : 'screens.scan.draft_title'),
      body: ScanDraftSheet(
        barcode: entry.barcode,
        name: entry.productName,
        brand: entry.brand,
        provenance: _provenanceOf(entry.source),
        // A product the tenant already owns is shown rather than offered for renaming: the commit
        // would send a card to create and the server refuses that, because the barcode is already
        // linked to their product.
        editable: entry.productId == null,
        confirming: found,
      ),
    );

    if (!mounted) return;

    if (draft == null) {
      // **Closing the card still answers the question it asked.** The row keeps what the cascade said
      // and will be written as it stands, so re-opening on the next read of the same box would ask
      // about an answer the user has already looked at and accepted by leaving it alone.
      _controller.markAsked(entry.barcode, symbology: entry.symbology);

      return;
    }

    _controller.fill(
      entry.barcode,
      symbology: entry.symbology,
      name: draft.name,
      unit: draft.baseUnit,
      brand: draft.brand,
      contribute: draft.contribute,
    );
  }

  /// Where an answer came from, already localised, or null when nothing answered.
  ///
  /// `own` prints nothing: a product the tenant already holds needs no provenance, which is the same
  /// rule `ScanRow` follows for the row itself.
  String? _provenanceOf(ScanSource source) => switch (source) {
    ScanSource.own => null,
    ScanSource.unmatched => null,
    ScanSource.catalog => Lang.get('screens.scan.from_catalog'),
    ScanSource.unverified => Lang.get('screens.scan.from_unverified'),
    ScanSource.recalled => Lang.get('screens.scan.from_recalled'),
  };

  /// Reads whatever the user typed, then clears the field for the next one.
  ///
  /// **Cleared after the call is dispatched, not after it returns.** A receiving bench types the
  /// next code while the last one is still resolving, and a field that clears late eats the first
  /// digits of the next read.
  void _submitManual() {
    final String code = _manual.text.trim();

    if (code.isEmpty) return;

    _manual.clear();
    unawaited(_scanThenPrompt(code, null));
  }


  @override
  Widget build(BuildContext context) {
    return MSPageScaffold(
      title: Lang.get('screens.scan.title'),
      // Pluralised on the SCAN count, which is the noun that inflects here: `:ready ready` is a
      // count plus an adjective and agrees with nothing. One barcode read `1 barcodes · 1 ready`
      // until Anılcan saw it on screen.
      subtitle: hasScans
          ? plural('screens.scan.subtitle', _scans.length, {
              'scans': _scans.length,
              'ready': _settled.length,
            })
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

  /// Whether both capture paths fit on screen together.
  bool get _bothFit => MediaQuery.sizeOf(context).width >= _bothFitWidth;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // **A window widened from phone to desktop size puts the viewfinder back on screen**, and a camera
    // stopped for the keyboard would be a black rectangle sitting there. Web is where this happens: it
    // is the one platform whose window changes width under a running app. A rebuild is already in
    // progress here, so the field is set directly rather than through `setState`.
    if (_bothFit && _typing) {
      _typing = false;
      unawaited(_scanner.start());
    }
  }

  /// Moves the phone's screen between the viewfinder and the digit field.
  ///
  /// **The camera is stopped rather than just hidden.** The controller outlives the widget, so removing
  /// the preview from the tree leaves the stream open: the torch stays lit behind a keyboard nobody can
  /// see past, and the battery goes on draining for a picture nothing is looking at.
  Future<void> _setTyping(bool typing) async {
    if (_typing == typing) return;

    setState(() => _typing = typing);

    if (typing) {
      await _scanner.stop();

      // Stopping releases the lamp, so the glyph would otherwise keep claiming a torch that is off.
      if (mounted && _torchOn) setState(() => _torchOn = false);

      return;
    }

    await _scanner.start();
  }

  /// The two ways a barcode gets in: the camera, and typed digits.
  ///
  /// Branched in Dart rather than with `hidden lg:flex`, and that is the exception the anti-pattern
  /// table allows rather than a lapse: the two arms differ in whether the CAMERA IS RUNNING, which a
  /// className cannot say. Using both mechanisms would be two sources of truth for one decision, so
  /// the width is read once, here.
  Widget _buildCapture() {
    final bool bothFit = _bothFit;

    return WDiv(
      className: 'flex flex-col gap-4 w-full lg:flex-1',
      children: [
        if (!bothFit) _buildModeSwitch(),
        if (bothFit || !_typing) ...[_buildViewfinder(), _buildCameraHint()],
        if (bothFit || _typing) _buildManualEntry(),
      ],
    );
  }

  /// Which capture path has the phone's screen.
  ///
  /// A segmented control, which is the shape `design.md` names for adjacent choices: one container with
  /// the selected segment raised inside it, so it reads as one control with a position rather than as
  /// two things that happen to sit next to each other. The labels are nominal, because a segment names
  /// a mode rather than issuing a command.
  ///
  /// **Built here rather than with `MSSegmentedControl`, and the reason is measured.** That control
  /// exposes `root` and `item` classNames, but `item` lands on a `WDiv` INSIDE a `WAnchor`, so the flex
  /// child of its row is the anchor and `flex-1` on `item` reaches the wrong box: `root: w-full`
  /// stretched the track and left both segments content-sized at the left edge. Full width from the
  /// caller is not expressible, so it belongs in that control as a PR to `magic_starter` rather than as
  /// an edit from here.
  ///
  /// The layering is the pattern the anti-pattern table prescribes for exactly this: the outer `WDiv`
  /// carries paint-only tokens, and a plain `Row` owns the main axis so `Expanded` is legal. A raw
  /// `Expanded` inside a wind `flex` box asserts as `RenderBox was not laid out` instead.
  Widget _buildModeSwitch() {
    return WDiv(
      className: 'w-full rounded-lg bg-surface-container-high p-1',
      child: Row(
        children: <Widget>[
          Expanded(child: _modeSegment(Lang.get('screens.scan.mode_camera'), !_typing, false)),
          Expanded(child: _modeSegment(Lang.get('screens.scan.mode_manual'), _typing, true)),
        ],
      ),
    );
  }

  /// One segment, carrying the same signals the library control uses: the fill, a hairline shadow and
  /// the text tone. Three together rather than the fill alone, which `design.md` asks for.
  Widget _modeSegment(String label, bool isSelected, bool typing) {
    return WAnchor(
      onTap: () => unawaited(_setTyping(typing)),
      semanticLabel: label,
      child: WDiv(
        className: isSelected
            ? 'flex flex-row items-center justify-center px-3 py-2 rounded-md bg-surface shadow-sm'
            : 'flex flex-row items-center justify-center px-3 py-2 rounded-md',
        child: WText(
          label,
          className: isSelected
              ? 'text-sm font-medium text-fg'
              : 'text-sm font-medium text-fg-muted',
        ),
      ),
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
                  placeholder: Lang.get('screens.scan.barcode_placeholder'),
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
      count: plural('screens.scan.scan_count', _scans.length, {'count': _scans.length}),
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
            pending: scan.pending,
            // **Every row opens the same sheet, and that is the point.** An unmatched one opens it
            // empty because nothing anywhere knew the code; a found one opens it PREFILLED, because a
            // catalogue answer can be wrong or in another language and the person holding the carton
            // is the one who can see that. It used to navigate to `/draft`, which is a fixture screen
            // that never learned the barcode.
            // Null while the lookup is out, because there is nothing to confirm yet and a card
            // opened now would be overwritten the moment the answer lands. The row still counts.
            onTap: scan.pending ? null : () => unawaited(_openDraft(scan)),
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
                WText(
                  // Null means this tenant has never received anything, which is a first delivery
                  // rather than a failure: the copy asks for a location instead of naming one.
                  _destinationPath ?? Lang.get('screens.scan.no_destination'),
                  className: 'flex-1 min-w-0 truncate text-sm text-fg',
                ),
                MSButton(
                  onPressed: _pickDestination,
                  intent: ButtonIntent.ghost,
                  className: 'justify-center shrink-0',
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
        //
        // **Two fragments and a wrapper, rather than one string with two counts.** Products and
        // unmatched barcodes inflect independently, so a single pipe would be wrong for every case
        // where they differ, and `localization_test` guards exactly that shape.
        WText(_writeSummary(ready, unmatched), className: 'text-sm text-fg-muted'),
        MSButton(
          // **`disabled` as well as a null callback**, because MSButton takes them separately: a
          // null `onPressed` alone leaves the primary fill looking untouched, which this repo has
          // already been bitten by once.
          onPressed: _controller.isCommitting || ready == 0 ? null : _commit,
          disabled: _controller.isCommitting || ready == 0,
          fullWidth: true,
          className: 'justify-center',
          child: WText(
            _controller.isCommitting
                ? Lang.get('screens.scan.submitting')
                : plural('screens.scan.submit', ready, {'count': ready}),
          ),
        ),
        // The server's own sentence when it refused, because it names the reason: a barcode already
        // in use, a serial-tracked product, a location that vanished. Replacing it with a generic
        // line throws away the only useful part of a refusal.
        if (_error != null) WText(_error!, className: 'text-sm text-expired'),
      ],
    );
  }

  /// What committing will write, and what it will leave behind.
  ///
  /// Both nouns are counted and they inflect on their own, so each is pluralised separately and the
  /// wrapper key holds only the separator. Composing in Dart with a hardcoded comma would put copy
  /// in a widget, which is what the catalogues exist to prevent.
  String _writeSummary(int ready, int unmatched) {
    final String written = plural('screens.scan.will_write', ready, {'count': ready});

    if (unmatched == 0) {
      return written;
    }

    return Lang.get('screens.scan.will_write_partial', {
      'ready': written,
      'unmatched': plural('screens.scan.unmatched_count', unmatched, {'unmatched': unmatched}),
    });
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
