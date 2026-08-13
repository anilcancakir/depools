import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart'
    show ButtonIntent, ButtonSize, MSBottomSheet, MSButton, MSInput, MSSwitch;
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../app/support/scan_outcome.dart';
import 'product_fixtures.dart' show ProductListItem;

/// Counting a shelf by reading labels, with the list still visible above.
///
/// ### Why a panel rather than a screen
///
/// A full-screen camera is the better viewfinder and the worse count: the rows already counted go
/// off screen, so a user cannot see what they have done until they close it. Half the height keeps
/// both, which is what the count is for. `barcode-and-catalog.md`'s third acceptance criterion is
/// that twenty items produce twenty resolutions without closing the camera, so this stays open and
/// accumulates rather than resolving one read and dismissing.
///
/// ### A scan is +1, and that is a mode rather than a law
///
/// Scanning the same code twice records two, which is what the category does: Odoo's own example
/// reads "scanned three times, increasing the units", and Katana, Cin7 and Stocky all say the same.
/// The asymmetry with receiving is real though, and it is why the switch exists: in receiving a
/// duplicate read has an arrival behind it, while in a count the number IS the assertion, so an
/// accidental double read silently inflates it. Lightspeed shipped unconditional `+1` and added a
/// named toggle in its next generation; Sortly ships one off by default. This follows the majority
/// on the default and keeps their escape hatch.
///
/// ### Manual entry is a control, not a fallback
///
/// `scanWindow` is unsupported on web and web autofocus is unreliable, so on a laptop the camera is
/// worse than typing. The field is also how a desktop barcode reader works, since it is an HID
/// keyboard that types digits and presses enter.
class CountScannerSheet extends StatefulWidget {
  /// The shelf being counted, for the sheet's own title and for the wrong-shelf question.
  final String shelfLabel;

  /// Resolves a read against the shelf. Null means the question never got an answer.
  final Future<ScanOutcome?> Function(String code, {String? symbology}) resolve;

  /// Called for every read the user accepted, with how many units it adds.
  final void Function(ProductListItem product, num quantity) onCounted;

  /// Creates the sheet.
  const CountScannerSheet({
    super.key,
    required this.shelfLabel,
    required this.resolve,
    required this.onCounted,
  });

  /// Opens the panel and resolves with the codes that matched nothing.
  static Future<List<String>?> show(
    BuildContext context, {
    required String shelfLabel,
    required Future<ScanOutcome?> Function(String code, {String? symbology}) resolve,
    required void Function(ProductListItem product, num quantity) onCounted,
  }) {
    return MSBottomSheet.show<List<String>>(
      context,
      title: Lang.get('screens.count_scanner.title', {'location': shelfLabel}),
      body: CountScannerSheet(
        shelfLabel: shelfLabel,
        resolve: resolve,
        onCounted: onCounted,
      ),
    );
  }

  @override
  State<CountScannerSheet> createState() => _CountScannerSheetState();
}

class _CountScannerSheetState extends State<CountScannerSheet> {
  static const IconData _typeIcon = Icons.keyboard_outlined;
  static const IconData _okIcon = Icons.check_circle_outline;
  static const IconData _askIcon = Icons.help_outline;
  static const IconData _unknownIcon = Icons.help_center_outlined;

  /// How long the same code is ignored after it lands.
  ///
  /// **This is about the decode loop, not about the user.** A camera stream re-emits the barcode in
  /// front of it many times a second, so without a window one presentation of one label would count
  /// dozens. It has to stay short enough that a genuine second unit, presented deliberately, still
  /// counts: `DetectionSpeed.noDuplicates` would suppress that forever, which is the wrong answer
  /// for a mode whose whole point is that scanning twice records two.
  static const Duration _sameCodeWindow = Duration(milliseconds: 1200);

  /// Every format the platform can read, which is the package's own default.
  ///
  /// **No `formats:` argument, deliberately.** Passing `const <BarcodeFormat>[]` says the same thing
  /// (`mobile_scanner`'s own doc comment: "If this is empty, all supported formats are detected") and
  /// reads like the opposite, which a reviewer took it for twice. Narrowing the list would be wrong
  /// here anyway: a shelf carries EAN-13 on the groceries, Code128 on a shop's own repacks and the
  /// occasional QR, and a count cannot know in advance which one is in front of the camera.
  late final MobileScannerController _scanner = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    detectionTimeoutMs: _sameCodeWindow.inMilliseconds,
  );

  final TextEditingController _typed = TextEditingController();

  /// Codes that matched nothing, in the order they were read, without duplicates.
  final List<String> _unknown = <String>[];

  /// What happened to the last few reads, newest first.
  final List<_ScanEntry> _log = <_ScanEntry>[];

  /// Whether a scan counts by itself, or selects a product for the user to type a number into.
  bool _countOnScan = true;

  /// Whether a lookup is in flight, so a burst of reads cannot start several.
  bool _resolving = false;

  @override
  void dispose() {
    _scanner.dispose();
    _typed.dispose();
    super.dispose();
  }

  /// The symbology name the API expects, or null for a format that carries a GTIN.
  ///
  /// Lower-cased because the server stores it that way; the enum's own name is camelCase. It is only
  /// sent for the formats where it is part of the identity, since a GTIN needs no help: the same
  /// digits as an EAN-13 and as a UPC-A are one product, and saying which reader saw it would split
  /// them.
  String? _symbologyOf(BarcodeFormat format) {
    const Set<BarcodeFormat> gtinBearing = <BarcodeFormat>{
      BarcodeFormat.ean8,
      BarcodeFormat.ean13,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.itf14,
    };

    return gtinBearing.contains(format) ? null : format.name.toLowerCase();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    final Barcode? read = capture.barcodes.firstOrNull;
    final String? value = read?.rawValue;

    if (read == null || value == null || value.isEmpty) return;

    await _handle(value, symbology: _symbologyOf(read.format));
  }

  Future<void> _handle(String code, {String? symbology}) async {
    // One question at a time. A live camera can deliver several reads while the first is still in
    // flight, and letting them race would count a product twice for one presentation.
    if (_resolving) return;

    setState(() => _resolving = true);

    final ScanOutcome? outcome = await widget.resolve(code, symbology: symbology);

    if (!mounted) return;

    setState(() => _resolving = false);

    // Null is a failed question rather than an unknown product, and saying otherwise would send the
    // user to create a product they already own.
    if (outcome == null) {
      _remember(_ScanEntry.failed(code));

      return;
    }

    switch (outcome.verdict) {
      case ScanVerdict.onShelf:
        _accept(outcome.product!);
      case ScanVerdict.elsewhere:
        await _askAboutElsewhere(outcome.product!);
      case ScanVerdict.unknown:
        setState(() {
          if (!_unknown.contains(code)) _unknown.add(code);
        });
        _remember(_ScanEntry.unknown(code));
    }
  }

  /// Counts one unit of [product], or hands it to the sheet's caller to be typed into.
  void _accept(ProductListItem product) {
    widget.onCounted(product, _countOnScan ? 1 : 0);
    _remember(_ScanEntry.counted(product.name, counted: _countOnScan));
  }

  /// Asks before counting a product the record keeps somewhere else.
  ///
  /// **The question exists because agreeing silently writes a movement.** The category does not ask:
  /// Katana adds the row and moves on. That is defensible when a scan is a lookup and wrong here,
  /// where the number becomes a ledger entry the user cannot delete, only compensate.
  Future<void> _askAboutElsewhere(ProductListItem product) async {
    final bool? here = await MSBottomSheet.show<bool>(
      context,
      title: Lang.get('screens.count_scanner.elsewhere_title'),
      body: WDiv(
        className: 'flex flex-col gap-3',
        children: [
          WText(
            Lang.get('screens.count_scanner.elsewhere_body', {
              'product': product.name,
              'location': product.locationSummary.isEmpty
                  ? Lang.get('screens.count_scanner.nowhere')
                  : product.locationSummary,
              'shelf': widget.shelfLabel,
            }),
            className: 'text-sm text-fg-muted',
          ),
          Builder(
            builder: (BuildContext sheetContext) => WDiv(
              className: 'flex flex-row items-center gap-2',
              children: [
                MSButton(
                  onPressed: () => Navigator.of(sheetContext).pop(false),
                  intent: ButtonIntent.secondary,
                  className: 'h-11 justify-center flex-1',
                  child: WText(Lang.get('screens.count_scanner.elsewhere_skip')),
                ),
                MSButton(
                  onPressed: () => Navigator.of(sheetContext).pop(true),
                  className: 'h-11 justify-center flex-1',
                  child: WText(Lang.get('screens.count_scanner.elsewhere_count')),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (here == true) {
      _accept(product);

      return;
    }

    _remember(_ScanEntry.skipped(product.name));
  }

  void _remember(_ScanEntry entry) {
    setState(() {
      _log.insert(0, entry);

      // Ordered by LAST read rather than by first seen, and capped: a live camera fills this faster
      // than anyone reads it, and what matters is feedback for the read just taken.
      if (_log.length > 4) _log.removeLast();
    });
  }

  Future<void> _submitTyped() async {
    final String code = _typed.text.trim();

    // **Guarded BEFORE the field is cleared, or a typed code disappears with no feedback.** The
    // clear used to come first and `_handle` returns early while a lookup is in flight, so a second
    // entry during that window emptied the field and did nothing else. Silent, and reachable from
    // the keyboard rather than only from the button: `onSubmitted` has no disabled state to respect.
    //
    // Leaving the text in place is itself the feedback. The user's entry is still there to send
    // again, which is what they would want anyway, and it needs no message to say so.
    if (code.isEmpty || _resolving) return;

    _typed.clear();

    // No symbology, because a typed code is digits the user read off a label rather than a decode.
    // The server treats a digits-only value as a GTIN, which is what a printed number under a
    // barcode is.
    await _handle(code);
  }

  @override
  Widget build(BuildContext context) {
    return WDiv(
      className: 'flex flex-col gap-3',
      children: [
        _buildViewfinder(context),
        _buildMode(),
        _buildManualEntry(),
        if (_log.isNotEmpty) _buildLog(),
        _buildDone(),
      ],
    );
  }

  /// Closes the panel, handing back the codes that matched nothing.
  ///
  /// **The unknown codes leave with the sheet rather than being dealt with inside it.** Defining a
  /// product takes a name, a unit and a shelf life, which is a form and not a thing to fill in at a
  /// shelf with a phone in one hand; interrupting a count of twenty for the third of them that is
  /// unrecognised is how the count stops being finished. They are collected here and offered once,
  /// afterwards, by the screen that has room to offer them.
  Widget _buildDone() {
    return Builder(
      builder: (BuildContext sheetContext) => MSButton(
        onPressed: () => Navigator.of(sheetContext).pop(_unknown),
        fullWidth: true,
        className: 'h-11 justify-center',
        child: WText(
          _unknown.isEmpty
              ? Lang.get('screens.count_scanner.done')
              : Lang.get('screens.count_scanner.done_with_unknown', {'count': _unknown.length}),
        ),
      ),
    );
  }

  Widget _buildViewfinder(BuildContext context) {
    // A third of the window rather than a fixed height: the sheet has to leave the count list
    // visible above it, and a constant would be right on one device only.
    final double height = (MediaQuery.sizeOf(context).height / 3).clamp(180, 320);

    return WDiv(
      className: 'relative rounded-lg overflow-hidden bg-ink',
      children: [
        SizedBox(
          height: height,
          width: double.infinity,
          child: MobileScanner(controller: _scanner, onDetect: _onDetect),
        ),
      ],
    );
  }

  Widget _buildMode() {
    return WDiv(
      className: 'flex flex-row items-center gap-3',
      children: [
        WDiv(
          className: 'flex-1 min-w-0 flex flex-col gap-1',
          children: [
            WText(
              Lang.get('screens.count_scanner.count_on_scan'),
              className: 'text-sm font-medium text-fg',
            ),
            WText(
              Lang.get(
                _countOnScan
                    ? 'screens.count_scanner.count_on_scan_hint'
                    : 'screens.count_scanner.select_on_scan_hint',
              ),
              className: 'text-xs text-fg-muted',
            ),
          ],
        ),
        MSSwitch(
          value: _countOnScan,
          // The control's shape is its whole appearance, so it needs the edge token DESIGN.md added
          // for exactly this: on a white card its off track measured 1.21:1 without one.
          className: 'border border-color-control',
          onChanged: (bool next) => setState(() => _countOnScan = next),
        ),
      ],
    );
  }

  Widget _buildManualEntry() {
    return WDiv(
      className: 'flex flex-row items-center gap-2',
      children: [
        WDiv(
          className: 'flex-1 min-w-0',
          child: MSInput(
            className: 'h-11 bg-surface-container',
            placeholder: Lang.get('screens.count_scanner.type_code'),
            prefix: const WIcon(_typeIcon, className: 'size-4 text-fg-muted'),
            controller: _typed,
            onSubmitted: (_) => _submitTyped(),
          ),
        ),
        MSButton(
          // Both, and the second is the one that shows. `MSButton` takes `disabled` separately from
          // `onPressed`, so a null callback alone leaves a button that looks live and does nothing,
          // which is how a user ends up tapping it twice and believing the app is stuck.
          disabled: _resolving,
          onPressed: _resolving ? null : _submitTyped,
          size: ButtonSize.sm,
          className: 'h-11 justify-center shrink-0',
          child: WText(Lang.get('screens.count_scanner.type_submit')),
        ),
      ],
    );
  }

  Widget _buildLog() {
    return WDiv(
      className: 'flex flex-col gap-2',
      children: [
        for (final _ScanEntry entry in _log)
          WDiv(
            className: 'flex flex-row items-center gap-2',
            children: [
              WIcon(entry.icon, className: 'size-4 ${entry.tone} shrink-0'),
              WText(entry.label, className: 'flex-1 min-w-0 truncate text-sm text-fg'),
            ],
          ),
      ],
    );
  }
}

/// One line of feedback about a read, which is the only thing telling the user it landed.
///
/// Scanning is done at arm's length with the phone pointed away, so the screen is the confirmation.
/// Every branch produces one, including the ones that counted nothing: silence after a read is
/// indistinguishable from a camera that has stopped working.
class _ScanEntry {
  final String label;
  final IconData icon;
  final String tone;

  const _ScanEntry({required this.label, required this.icon, required this.tone});

  factory _ScanEntry.counted(String name, {required bool counted}) => _ScanEntry(
    label: counted
        ? Lang.get('screens.count_scanner.log_counted', {'product': name})
        : Lang.get('screens.count_scanner.log_selected', {'product': name}),
    icon: _CountScannerSheetState._okIcon,
    tone: 'text-in-stock',
  );

  factory _ScanEntry.skipped(String name) => _ScanEntry(
    label: Lang.get('screens.count_scanner.log_skipped', {'product': name}),
    icon: _CountScannerSheetState._askIcon,
    tone: 'text-fg-muted',
  );

  factory _ScanEntry.unknown(String code) => _ScanEntry(
    label: Lang.get('screens.count_scanner.log_unknown', {'code': code}),
    icon: _CountScannerSheetState._unknownIcon,
    tone: 'text-fg-muted',
  );

  factory _ScanEntry.failed(String code) => _ScanEntry(
    label: Lang.get('screens.count_scanner.log_failed', {'code': code}),
    icon: _CountScannerSheetState._askIcon,
    tone: 'text-expired',
  );
}
