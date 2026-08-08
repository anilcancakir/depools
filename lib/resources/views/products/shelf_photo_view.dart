import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart'
    show MSPageScaffold, MSButton, ButtonIntent, MSSkeleton, SkeletonShape;

import '../../../ui/components/callout/callout.dart';
import '../../../ui/components/section_card/section_card.dart';
import '../../../ui/components/shelf_candidate_row/shelf_candidate_row.dart';
import 'shelf_fixtures.dart';

/// How far the read has got.
enum ShelfReadState {
  /// The model is still working. The MVP showed a blank screen here for two minutes.
  reading,

  /// Finished, and waiting for the user.
  ready,

  /// It could not be read. The photograph is kept.
  failed,
}

/// Reviewing a shelf photograph before any of it becomes stock.
///
/// **The photograph stays on screen with numbered boxes, and every row carries its number**
/// (D60). `ai-enrichment.md` sketches a film strip of candidates, and a strip of crops is the
/// weaker version of the same idea: the photograph IS the strip, so drawing boxes on it and
/// numbering the rows to match gives the spatial link without a second set of images. It also
/// works without hover or tap state, which a static review and a screen reader both need.
///
/// **The read is never a blank screen.** The MVP left users watching nothing through a
/// two-minute image analysis, so the reading state shows the photograph immediately, the boxes
/// as they are found, and a count of how far it has got. Rows arrive progressively underneath.
///
/// **A failed read keeps the photograph.** `ai-design.md` requires a failed capture to leave a
/// resumable record rather than an orphaned file, so the failure state still shows the picture,
/// says what happened, and offers the two ways forward. Nothing is thrown away on the user's
/// behalf.
///
/// **One photograph is one credit however many products it yields**, which
/// `ai-enrichment.md` calls worth telling users, because it makes this the cheapest capture
/// path in the app and nobody would guess that from the interface.
@immutable
class ShelfPhotoView extends StatelessWidget {
  static const IconData _retakeIcon = Icons.photo_camera_outlined;
  static const IconData _manualIcon = Icons.edit_outlined;

  /// How far the read has got.
  final ShelfReadState state;

  /// Creates the view with the read finished.
  const ShelfPhotoView({super.key}) : state = ShelfReadState.ready;

  /// Creates the view mid-read.
  const ShelfPhotoView.reading({super.key}) : state = ShelfReadState.reading;

  /// Creates the view after a failed read.
  const ShelfPhotoView.failed({super.key}) : state = ShelfReadState.failed;

  /// How many boxes are drawn. Mid-read only the finished ones exist.
  int get _visibleRegions => switch (state) {
    ShelfReadState.reading => resolvedSoFar,
    ShelfReadState.ready => shelfCandidates.length,
    ShelfReadState.failed => 0,
  };

  @override
  Widget build(BuildContext context) {
    return MSPageScaffold(
      title: 'Raf fotoğrafı',
      subtitle: switch (state) {
        ShelfReadState.reading =>
          'Okunuyor · $resolvedSoFar / ${shelfCandidates.length} bölge çözüldü',
        ShelfReadState.ready =>
          '${shelfCandidates.length} bölge · ${settledCandidates.length} ürün hazır',
        ShelfReadState.failed => 'Okunamadı',
      },
      children: [
        _buildPhoto(),
        if (state == ShelfReadState.failed) _buildFailure() else _buildCandidates(),
        _buildActions(),
      ],
    );
  }

  /// The photograph, with a numbered box per finished region.
  ///
  /// Wind paints the surfaces and Flutter measures the geometry: the boxes are fractions of
  /// the picture, so they need the real constraints, and a `Stack` of `Positioned` children is
  /// the only honest way to place them. Interpolating a computed value into a className is
  /// forbidden and would break the parser cache anyway.
  Widget _buildPhoto() {
    return SectionCard(
      label: 'Fotoğraf',
      count: state == ShelfReadState.failed ? null : '$_visibleRegions bölge',
      children: [
        WDiv(
          className: 'w-full rounded-md bg-surface-container-high overflow-hidden',
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: LayoutBuilder(
              builder: (context, constraints) => Stack(
                children: <Widget>[
                  // The picture itself. A placeholder here; the real screen shows the capture.
                  const Positioned.fill(
                    child: WDiv(
                      className: 'flex flex-col items-center justify-center',
                      child: WIcon(Icons.photo_outlined, className: 'size-10 text-fg-disabled'),
                    ),
                  ),
                  for (final ShelfCandidate c in shelfCandidates.take(_visibleRegions))
                    Positioned(
                      left: c.left * constraints.maxWidth,
                      top: c.top * constraints.maxHeight,
                      width: c.width * constraints.maxWidth,
                      height: c.height * constraints.maxHeight,
                      child: _buildBox(c),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// One region's box, labelled with the number its row carries.
  ///
  /// The number sits in a filled badge rather than as bare text on the picture, because a
  /// photograph is an uncontrolled background: bare text is legible over a dark bottle and
  /// invisible over a white label.
  Widget _buildBox(ShelfCandidate candidate) {
    // **Two concentric strokes, and the pair is what makes it legible over any photograph.**
    //
    // This box sits on an UNCONTROLLED background. `border-color-border` is a `#D1D1D6` hairline
    // that vanishes over a white shelf label, and `border-bg-primary` was tried and DROPPED
    // SILENTLY: wind's alias expander matches a WHOLE token against a key, there is no
    // `border-bg-primary` key, the border parser then sees a colour it does not know, and the
    // boxes disappeared entirely.
    //
    // A single colour cannot solve this, which is why DESIGN.md deferred the token: the right hex
    // depends on the image. A pair escapes the dependency by arithmetic rather than by taste. For
    // a background of luminance L, contrast to the light stroke and contrast to the dark stroke
    // move in opposite directions, so the better of the two never falls below 3.91:1 with these
    // values, whatever the photograph does. See `lib/config/depools_overlay_tokens.dart`; the
    // floor is checked in `bin/verify-design-contrast.py` rather than asserted here.
    //
    // Ink outside and paper inside, because the outer edge meets the photograph at a hard
    // boundary and the darker stroke reads as a shadow there, which is what an edge over an image
    // is expected to look like.
    return WDiv(
      className: 'border-2 border-color-overlay-ink rounded-sm',
      child: WDiv(
        className: 'border-2 border-color-overlay-paper rounded-sm flex flex-col items-start',
        child: WDiv(
          className: 'size-5 rounded-sm bg-primary flex items-center justify-center',
          child: WText(
            '${candidate.region}',
            className: 'font-mono text-xs font-semibold text-on-primary',
          ),
        ),
      ),
    );
  }

  /// The rows, arriving progressively while the read runs.
  Widget _buildCandidates() {
    final bool isReading = state == ShelfReadState.reading;
    final List<ShelfCandidate> shown = shelfCandidates.take(_visibleRegions).toList();

    return SectionCard(
      label: 'Bulunanlar',
      count: '${shown.length} bölge',
      children: [
        for (final ShelfCandidate c in shown)
          ShelfCandidateRow(
            region: c.region,
            productName: c.productName,
            resolution: c.resolution,
            amount: c.amount,
            formatted: c.formatted,
            unit: c.unit,
            meta: c.meta,
            onTap: () {},
          ),
        // A skeleton for the regions still being read, so the list says "more is coming"
        // rather than looking finished at four.
        if (isReading)
          WDiv(
            className: 'flex flex-row items-center gap-3 py-2',
            children: const [
              MSSkeleton(shape: SkeletonShape.circle, width: 24, height: 24),
              MSSkeleton(shape: SkeletonShape.text, width: 160, height: 16),
            ],
          ),
      ],
    );
  }

  /// The read failed, and the photograph is still here.
  Widget _buildFailure() {
    return SectionCard(
      label: 'Sonuç',
      children: const [
        Callout(
          intent: CalloutIntent.danger,
          title: 'Fotoğraf okunamadı',
          // Says what was kept, because the MVP's failure mode was an uploaded file with
          // nothing pointing at it and a user who had to start over.
          message:
              'Fotoğraf saklandı, kredi harcanmadı. Yeniden denenebilir ya da ürünler '
              'elle eklenebilir.',
        ),
      ],
    );
  }

  /// Accept what is settled, or take one of the two ways out.
  ///
  /// The count on the button is the SETTLED count, not the region count. Six regions yielded
  /// four products; a button reading "6 ürünü ekle" would promise to write an unnamed bottle
  /// and a price label.
  Widget _buildActions() {
    final int ready = settledCandidates.length;

    return WDiv(
      className: 'flex flex-col gap-2 pb-2',
      children: [
        if (state == ShelfReadState.ready) ...[
          WText(
            unresolvedCandidates.isEmpty
                ? '$ready ürün stoğa yazılacak'
                : '$ready ürün stoğa yazılacak, ${unresolvedCandidates.length} bölge '
                      'tanınamadı',
            className: 'text-sm text-fg-muted',
          ),
          // The economics, stated once. It is the cheapest capture path in the app and
          // nothing in the interface would say so.
          WText(
            'Tek fotoğraf 1 kredi · kaç ürün bulunursa bulunsun',
            className: 'text-xs text-fg-muted',
          ),
          MSButton(
            onPressed: () {},
            fullWidth: true,
            className: 'justify-center',
            child: WText('$ready ürünü ekle'),
          ),
        ],
        MSButton(
          onPressed: () {},
          intent: ButtonIntent.ghost,
          fullWidth: true,
          className: 'justify-center',
          child: WDiv(
            className: 'flex flex-row items-center justify-center gap-2',
            children: [
              const WIcon(_retakeIcon, className: 'size-4'),
              WText(state == ShelfReadState.failed ? 'Yeniden dene' : 'Yeniden çek'),
            ],
          ),
        ),
        if (state != ShelfReadState.reading)
          MSButton(
            onPressed: () {},
            intent: ButtonIntent.ghost,
            fullWidth: true,
            className: 'justify-center',
            child: const WDiv(
              className: 'flex flex-row items-center justify-center gap-2',
              children: [
                WIcon(_manualIcon, className: 'size-4'),
                WText('Elle ekle'),
              ],
            ),
          ),
      ],
    );
  }
}
