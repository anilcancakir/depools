import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart'
    show MSPageScaffold, MSButton, ButtonIntent, MSEmptyState, MSInput;

import '../../../ui/components/scan_row/scan_row.dart';
import '../../../ui/components/section_card/section_card.dart';
import 'scan_fixtures.dart';

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
@immutable
class BarcodeScanView extends StatelessWidget {
  static const IconData _torchIcon = Icons.flashlight_on_outlined;
  static const IconData _cameraIcon = Icons.qr_code_scanner_outlined;
  static const IconData _emptyIcon = Icons.inventory_2_outlined;
  static const IconData _photoIcon = Icons.photo_camera_outlined;
  static const IconData _shelfIcon = Icons.grid_view_outlined;

  /// Whether anything has been scanned yet.
  ///
  /// Two variants rather than one, because the empty queue is not a rare state: it is what
  /// every scanning session starts as, and it is the moment a user decides whether the
  /// screen is working.
  final bool hasScans;

  /// Creates the [BarcodeScanView] with a batch in progress.
  const BarcodeScanView({super.key}) : hasScans = true;

  /// Creates the view as it opens, camera live and nothing read yet.
  const BarcodeScanView.empty({super.key}) : hasScans = false;

  /// The batch destination: the last location used for receiving.
  ///
  /// **Not category affinity, and that is a deliberate departure** from every other
  /// location suggestion in the app. Affinity answers "where does this CATEGORY go", which
  /// is exactly the question a mixed batch cannot ask: milk and a screwdriver set disagree,
  /// and picking one row's winner for the whole batch would be arbitrary dressed up as
  /// intelligence. Receiving location is a habit rather than a per-product fact, so the last
  /// one used is both the better guess and an honest one.
  static const String _destination = 'Depo › Raf A';

  @override
  Widget build(BuildContext context) {
    return MSPageScaffold(
      title: 'Barkod tara',
      subtitle: hasScans
          ? '${scanBatch.length} barkod · ${settledScans.length} ürün hazır'
          : 'Sürekli tarama',
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
      children: [_buildViewfinder(), _buildManualEntry()],
    );
  }

  /// The live camera area.
  ///
  /// Rendered as a tonal panel with a framing rectangle rather than corner brackets: the
  /// frame reads through a surface shift as well as its border, which is what DESIGN.md
  /// asks for before reaching for a border, and it does not depend on a border token that
  /// is deliberately low contrast.
  ///
  /// **The overlay is a separate layer from the panel, and it has to be.** A first pass put
  /// `relative` and the flex alignment on the same WDiv as the absolutely positioned torch.
  /// Wind turns a container with a positioned child into a Stack, and a Stack does not
  /// honour `items-center justify-center`, so the frame silently collapsed to the top-left
  /// corner of an otherwise empty panel. The stack now holds two children: the flex panel,
  /// and the overlay on top of it.
  Widget _buildViewfinder() {
    return WDiv(
      className: 'relative w-full',
      children: [
        WDiv(
          className: '''
            w-full h-56 md:h-64 rounded-lg bg-surface-container-high
            flex flex-col items-center justify-center gap-3
          ''',
          children: [
            WDiv(
              className: '''
                size-32 rounded-md border-2 border-color-border bg-surface-container
                flex flex-col items-center justify-center
              ''',
              child: const WIcon(_cameraIcon, className: 'size-10 text-fg-disabled'),
            ),
            // Nominal, not an instruction. The frame already says where to point the
            // camera.
            WText(
              hasScans ? 'Kamera açık · son okuma 8680000998877' : 'Kamera açık',
              className: 'text-xs text-fg-muted',
            ),
          ],
        ),
        // A torch is not a nicety here: half of all stock lives in a cupboard, a cellar or
        // the back of a van, and a scanner that cannot light its own target fails there.
        WDiv(
          className: 'absolute top-2 right-2',
          child: MSButton(
            onPressed: () {},
            intent: ButtonIntent.ghost,
            className: 'min-h-11 min-w-11 justify-center',
            semanticLabel: 'Fener',
            child: const WIcon(_torchIcon, className: 'size-5'),
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
        label: 'Barkod',
        children: [
          const MSInput(
            className: 'bg-surface-container',
            placeholder: '13 hane',
            type: InputType.number,
          ),
          // Checksum validation is the reason this field is not just a shortcut: a
          // mistyped EAN-13 is caught here rather than becoming a product nobody can
          // scan again.
          WText('Kontrol hanesi doğrulanır', className: 'text-xs text-fg-muted'),
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
      label: 'Tarananlar',
      count: '${scanBatch.length} barkod',
      children: [
        for (final ScanFixture scan in scanBatch)
          ScanRow(
            barcode: scan.barcode,
            productName: scan.productName,
            source: scan.source,
            count: scan.count,
            unit: scan.unit,
            onHandFormatted: scan.onHandFormatted,
            onTap: () {},
          ),
      ],
    );
  }

  /// The queue before the first read.
  Widget _buildEmptyQueue() {
    return SectionCard(
      label: 'Tarananlar',
      children: [
        WDiv(
          // Full width so MSEmptyState's own `items-center` has something to centre in.
          className: 'w-full',
          child: MSEmptyState(
            icon: _emptyIcon,
            title: 'Henüz okuma yok',
            description:
                'Okunan her barkod buraya eklenir. Aynı barkod tekrar okunduğunda '
                'yeni satır açılmaz, mevcut satırın adedi artar.',
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

    final int ready = settledScans.length;
    final int unmatched = unmatchedScans.length;

    return WDiv(
      className: 'flex flex-col gap-2 pb-2',
      children: [
        SectionCard(
          label: 'Nereye',
          children: [
            WDiv(
              className: 'flex flex-row items-center justify-between gap-3 py-1',
              children: [
                WText(_destination, className: 'text-sm text-fg flex-auto min-w-0'),
                MSButton(
                  onPressed: () {},
                  intent: ButtonIntent.ghost,
                  className: 'justify-center',
                  child: const WText('Değiştir'),
                ),
              ],
            ),
            WText(
              'Tüm parti buraya girer, sonrasında konumlar arası taşınabilir',
              className: 'text-xs text-fg-muted',
            ),
          ],
        ),
        // Products, never a quantity sum. The rows can be in different units, and adding
        // three kilos to four items produces a number that means nothing.
        WText(
          unmatched == 0
              ? '$ready ürün stoğa yazılacak'
              : '$ready ürün stoğa yazılacak, $unmatched barkod eşleştirilemedi',
          className: 'text-sm text-fg-muted',
        ),
        MSButton(
          onPressed: () {},
          fullWidth: true,
          className: 'justify-center',
          child: WText('$ready ürünü ekle'),
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
      label: 'Kamerayla başka yollar',
      children: [
        _photoPath(
          _photoIcon,
          'Fotoğraftan tanıt',
          'Tek ürün · taslak kart açılır',
          'Tek bir ürünü fotoğraftan tanıt',
        ),
        _photoPath(
          _shelfIcon,
          'Rafı tara',
          'Raf dolusu · her ürün için bir bölge',
          'Raf fotoğrafından ürünleri tanıt',
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
