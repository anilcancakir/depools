import 'dart:async';

import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart'
    show MSBottomSheet, MSButton, ButtonIntent, MSSkeleton, SkeletonShape;

import '../../../app/controllers/shelf_controller.dart';
import '../../../app/models/shelf_read.dart';
import '../../../app/support/merge_unit_codes.dart';
import '../../../app/support/photo_picker.dart';
import '../../../app/support/plural.dart';
import '../../../ui/components/callout/callout.dart';
import '../../../ui/components/receipt_line_row/receipt_line_row.dart' show LineResolution;
import '../../../ui/components/section_card/section_card.dart';
import '../../../ui/components/shelf_candidate_row/shelf_candidate_row.dart';
import '../../../ui/layouts/app_page_scaffold.dart';
import 'destination_sheet.dart';
import 'product_fixtures.dart' show ProductListItem;
import 'shelf_candidate_sheet.dart';

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
class ShelfPhotoView extends StatefulWidget {
  static const IconData _retakeIcon = Icons.photo_camera_outlined;
  static const IconData _manualIcon = Icons.edit_outlined;

  /// A read supplied by the caller, which is how the preview catalog stays offline.
  ///
  /// Null means "read [ShelfController]", which is what the route does. The state class only touches
  /// the controller when this is null, so a preview never issues a request. Same contract filled
  /// from a different source: this is the type the endpoint returns, so it cannot drift from the API
  /// the way a hand-built fixture would.
  final ShelfRead? preview;

  /// Which state to draw. Only consulted alongside [preview].
  final ShelfReadState previewState;

  /// Creates the [ShelfPhotoView], reading from [ShelfController].
  const ShelfPhotoView({super.key})
    : preview = null,
      previewState = ShelfReadState.ready;

  /// Creates the view over a supplied read, for the catalog.
  const ShelfPhotoView.preview(
    ShelfRead this.preview, {
    super.key,
    this.previewState = ShelfReadState.ready,
  });

  @override
  State<ShelfPhotoView> createState() => _ShelfPhotoViewState();
}

class _ShelfPhotoViewState extends State<ShelfPhotoView> {
  ShelfController? _controller;

  /// The photograph's bytes, read once.
  ///
  /// **`Image.memory` rather than `Image.file`, and that is the platform rule.** `dart:io` does not
  /// exist on web, and the server never serves its own copy back (a private disk with no route, on
  /// purpose), so the only picture the boxes can sit on is the local file, read through bytes that
  /// work everywhere `image_picker` does.
  Future<Uint8List>? _photoBytes;

  /// Where the shelf's stock can go.
  ///
  /// Fetched in the view rather than in the controller, which is what `BarcodeScanView` does with
  /// the same list and for the same reason: `DestinationOption` is the picker's own shape, and a
  /// controller building a view type would be the dependency pointing the wrong way.
  List<DestinationOption> _locations = const <DestinationOption>[];

  /// The units a product created from an unnamed region may be counted in.
  ///
  /// Fetched once for the screen rather than per sheet: a shelf of six unnamed regions opens six
  /// sheets, and a sheet that fetched its own list would issue the same request six times. Starts at
  /// the countable unit, which is the honest degradation the product form uses for the same list:
  /// every product can be counted in pieces.
  List<String> _units = const <String>['C62'];

  @override
  void initState() {
    super.initState();

    if (widget.preview == null) {
      final ShelfController controller = ShelfController.instance
        ..addListener(_onControllerChanged);

      _controller = controller;
      _photoBytes = controller.photo?.readAsBytes();

      unawaited(_loadLocations());
      unawaited(_loadUnits());
    }
  }

  /// Loads the places a shelf's stock can go.
  ///
  /// Not awaited by anything: the picker only opens once the user has reviewed the regions, which is
  /// several seconds away at the earliest, and blocking the first frame on it would delay the
  /// photograph `ai-enrichment.md` wants on screen immediately.
  Future<void> _loadLocations() async {
    final dynamic response = await Http.get('/locations');

    if (!mounted || !response.successful) return;

    final dynamic rows = response['data'];

    setState(() {
      _locations = <DestinationOption>[
        if (rows is List)
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
    });
  }

  /// Loads the units this tenant may pick, so a created product is not forced into pieces.
  ///
  /// Merged rather than assigned, for the reason the product form records: the answer can land after
  /// the user has already chosen, and overwriting would leave the combobox holding a value that is no
  /// longer among its options.
  Future<void> _loadUnits() async {
    final dynamic response = await Http.get('/units');

    if (!mounted || !response.successful) return;

    final dynamic rows = response['data'];

    if (rows is! List) return;

    final List<String> codes = <String>[
      for (final dynamic row in rows)
        if (row is Map && row['code'] is String) row['code'] as String,
    ];

    if (codes.isEmpty) return;

    setState(() {
      _units = mergeUnitCodes(fromServer: codes, known: _units, selected: _units.first);
    });
  }

  @override
  void dispose() {
    final ShelfController? controller = _controller;

    controller?.removeListener(_onControllerChanged);

    // **The capture does not outlive the screen, and it used to.** The controller is a type-keyed
    // singleton and `/shelf-photo` is a named route, so going back after a commit re-enters this
    // widget: with the read still published it drew the boxes of an already-written shelf over a
    // placeholder, offered an accept button counting its settled regions, and answered a second
    // submit with "N products written to stock" while the server skipped every answered candidate.
    //
    // Called after the listener is dropped so the `refreshUI` inside it cannot reach a disposed
    // `setState`, and outside the commit path's own `reset()`, which is idempotent.
    controller?.reset();

    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  /// The read being reviewed, or an empty one before the upload answers.
  ShelfRead get _read =>
      widget.preview ?? _controller?.read ?? const ShelfRead(id: '');

  /// How far the read has got.
  ///
  /// Derived rather than stored, because the three states are three facts about the controller: a
  /// request in flight, an answer with regions in it, and an answer with none.
  ShelfReadState get state {
    if (widget.preview != null) return widget.previewState;

    final ShelfController? controller = _controller;

    if (controller == null) return ShelfReadState.failed;
    if (controller.uploading || controller.reading) return ShelfReadState.reading;

    // **Empty is a FAILURE here and it is not on the product-photo path**, which is the one place
    // this screen and that one disagree. A shelf holding nothing recognisable is the state
    // `ai-enrichment.md` draws a failed read for: the picture stays, the callout says what was kept,
    // and both ways forward are offered. A single-product read with no card still has a card to
    // type into, so it has somewhere else to go.
    return _read.candidates.isEmpty ? ShelfReadState.failed : ShelfReadState.ready;
  }

  /// The regions to draw, which is all of them or none.
  ///
  /// **There is no partial state, and the spec was corrected rather than the code fudged.**
  /// `ai-enrichment.md` asked for a box drawn "as each region finishes" with a running count, and its
  /// own constraints section forbids fake latency in as many words ("the MVP added
  /// `sleep(rand(2,3))`... that is a small lie and it goes"). One model call returns everything at
  /// once, so there are no per-region completions: revealing them one by one would be the same lie
  /// with an animation instead of a sleep, and asking per region would be N+1 calls that destroy the
  /// one-credit economics this path exists for.
  ///
  /// So the honest reading state is the photograph, immediately, with skeleton rows underneath.
  List<ShelfCandidate> get _visible => switch (state) {
    ShelfReadState.reading => const <ShelfCandidate>[],
    ShelfReadState.ready => _read.candidates,
    ShelfReadState.failed => const <ShelfCandidate>[],
  };

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      title: Lang.get('screens.shelf_photo.title'),
      subtitle: switch (state) {
        // No count while it reads, because there is nothing to count yet and a `0 of 0` would be a
        // number pretending to be progress.
        ShelfReadState.reading => Lang.get('screens.shelf_photo.subtitle_reading'),
        // Each half pluralises on its own count, the way `barcode_scan_view` composes its own
        // two-count line: one string carrying two numbers can only agree with one of them.
        ShelfReadState.ready => Lang.get('screens.shelf_photo.subtitle', {
          'regions': plural('screens.shelf_photo.region_count', _read.candidates.length, {
            'count': _read.candidates.length,
          }),
          'ready': _read.settled.length,
        }),
        // **"Could not be read" is wrong when nothing was ever captured**, and this state resolves
        // to `failed` because there is no read: the enum has three values and `ai-enrichment.md`
        // pins them, so the fourth case is asked for here rather than added to it.
        ShelfReadState.failed => _isEmptyCapture
            ? Lang.get('screens.shelf_photo.subtitle_nothing')
            : Lang.get('screens.shelf_photo.subtitle_failed'),
      },
      // Pinned rather than trailing (D70). A photograph of a full shelf yields a candidate per
      // region, so accepting them sits under a list whose length the user does not control.
      footer: _buildActions(),
      children: [
        // **No photo card when there is no photograph.** D60 keeps the picture on screen through a
        // review and through a failure, because in both cases there IS one; on an empty capture the
        // card was a 4:3 placeholder taking the whole viewport to say nothing.
        if (!_isEmptyCapture) _buildPhoto(),
        if (state != ShelfReadState.failed)
          _buildCandidates()
        else if (!_isEmptyCapture)
          _buildFailure()
        else
          _buildNothing(),
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
      label: Lang.get('screens.shelf_photo.photo_group'),
      // **No count until there is one to give.** `0 regions` while the model is still working is
      // the same lie the subtitle refuses one line up: it reads as "nothing found" rather than as
      // "nothing back yet", and the read returns every region at once so there is no partial number
      // to print. Ready is the only state that has a count.
      count: state == ShelfReadState.ready
          ? plural('screens.shelf_photo.region_count', _visible.length, {'count': _visible.length})
          : null,
      children: [
        WDiv(
          className: 'w-full rounded-md bg-surface-container-high overflow-hidden',
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: LayoutBuilder(
              builder: (context, constraints) => Stack(
                children: <Widget>[
                  Positioned.fill(child: _buildPicture()),
                  for (final ShelfCandidate c in _visible)
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
    final List<ShelfCandidate> shown = _visible;

    return SectionCard(
      label: Lang.get('screens.shelf_photo.found_group'),
      count: isReading
          ? null
          : plural('screens.shelf_photo.region_count', shown.length, {'count': shown.length}),
      children: [
        for (final ShelfCandidate c in shown)
          ShelfCandidateRow(
            region: c.region,
            productName: c.productName,
            resolution: c.resolution,
            // **A quantity the model could not count is NOT zero, and printing `0` says it was.**
            // The row still gets 0 as the raw amount, because that drives its zero TONE and an
            // uncounted region is not a quantity to celebrate. Same split `ReceiptReviewView` makes.
            amount: c.quantity ?? 0,
            formatted: c.quantity == null
                ? Lang.get('screens.shelf_photo.quantity_unknown')
                : ProductListItem.format(c.quantity!),
            unit: c.unit ?? '',
            meta: _metaFor(c),
            onTap: () => _decide(context, c),
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

  /// Whether this screen was entered with nothing to show at all.
  ///
  /// No row, no refusal to report, so neither the photo card nor the failure callout applies. Reached
  /// by an ordinary back navigation now that the screen releases its capture on dispose, and
  /// previously the same route produced a failed-looking screen whose only button did nothing.
  bool get _isEmptyCapture => !_hasRead && _controller?.error == null;

  /// Whether the server ever answered with a row.
  ///
  /// The one thing that separates "the read failed" from "the upload failed", and the view had no way
  /// to ask it: on an upload refusal `setError` publishes null, so the screen fell into its failed
  /// state and offered to re-read a row that does not exist.
  bool get _hasRead => widget.preview != null || _controller?.read != null;

  /// The read failed, and what to say depends on which failure it was.
  ///
  /// Three cases, and the screen used to show one sentence for all of them:
  ///
  /// - **The upload was refused.** No row exists, so the server's own sentence is the only useful
  ///   thing to say, and `failed_note`'s "the photo is kept" was a claim about a file
  ///   `ShelfReadController::store` had already discarded.
  /// - **There were no credits.** `ai-enrichment.md` calls this the one outcome a user can act on,
  ///   and the model's own docblock claimed the screen branched on it when nothing did.
  /// - **The photograph could not be read.** The original case, unchanged.
  Widget _buildFailure() {
    final String? sentence = _controller?.error;

    if (!_hasRead) {
      return _failureCard(
        Lang.get('screens.shelf_photo.upload_failed_title'),
        sentence ?? Lang.get('screens.shelf_photo.nothing_note'),
      );
    }

    if (_read.lastReadOutcome == 'no_credit') {
      return _failureCard(
        Lang.get('screens.shelf_photo.no_credit_title'),
        Lang.get('screens.shelf_photo.no_credit_note'),
      );
    }

    return _failureCard(
      Lang.get('screens.shelf_photo.failed_title'),
      // Says what was kept, because the MVP's failure mode was an uploaded file with nothing
      // pointing at it and a user who had to start over. The server's own sentence leads when there
      // is one, because "could not be read" is what we say when we do not know why.
      sentence ?? Lang.get('screens.shelf_photo.failed_note'),
    );
  }

  /// One refusal, said once.
  Widget _failureCard(String title, String message) {
    return SectionCard(
      label: Lang.get('screens.shelf_photo.result_group'),
      children: [
        Callout(intent: CalloutIntent.danger, title: title, message: message),
      ],
    );
  }

  /// Nothing has been captured, so there is nothing to review.
  ///
  /// Reachable from an ordinary back navigation now that the screen releases its capture on dispose,
  /// and previously the same route produced the dead screen described on [_buildFailure].
  Widget _buildNothing() {
    return SectionCard(
      label: Lang.get('screens.shelf_photo.result_group'),
      children: [
        Callout(
          intent: CalloutIntent.info,
          title: Lang.get('screens.shelf_photo.nothing_title'),
          message: Lang.get('screens.shelf_photo.nothing_note'),
        ),
      ],
    );
  }

  /// The line under a row that says where it stands.
  ///
  /// Derived from the resolution rather than carried as a string, which is what the fixture used to
  /// do: a pre-localised field cannot be localised, and this screen ships in two languages.
  String? _metaFor(ShelfCandidate candidate) => switch (candidate.resolution) {
    LineResolution.matched => Lang.get('screens.shelf_photo.meta_matched'),
    LineResolution.created => Lang.get('screens.shelf_photo.meta_created'),
    LineResolution.rejected => Lang.get('screens.shelf_photo.meta_rejected'),
    LineResolution.unresolved => null,
  };

  /// Accept what is settled, or take one of the two ways out.
  ///
  /// The count on the button is the SETTLED count, not the region count. Six regions yielded
  /// four products; a button reading "6 ürünü ekle" would promise to write an unnamed bottle
  /// and a price label.
  /// Which of the three things that button can be.
  ///
  /// `retake` presumes a first photograph, so it is wrong on a screen entered with no capture at all:
  /// "Take another" of nothing. That state is reachable by an ordinary back navigation now that the
  /// screen releases its capture on dispose, so it earns its own word.
  ///
  /// The three keys are written out rather than interpolated into one `Lang.get`, because
  /// `lang_keys_exist_test` greps for a literal and an assembled key is the one thing neither copy
  /// gate can see (`flutter-app.md`: "parity is not presence").
  String get _retakeLabel {
    if (_canRetryRead) return Lang.get('screens.shelf_photo.retry');

    return _hasRead
        ? Lang.get('screens.shelf_photo.retake')
        : Lang.get('screens.shelf_photo.capture');
  }

  /// Whether a re-read is the right offer, which needs a row to re-read.
  bool get _canRetryRead => state == ShelfReadState.failed && _hasRead;

  /// Whether a request is in flight that the other buttons must not race.
  ///
  /// A commit publishes the read it answers with, so a retake or a walk-away accepted mid-commit
  /// would have the old read land on top of the new capture. The controller drops a stale publish on
  /// its own; this stops the user reaching the state in the first place.
  bool get _busy => _controller?.committing ?? false;

  Widget _buildActions() {
    final int ready = _read.settled.length;

    return WDiv(
      className: 'flex flex-col gap-2 pb-2',
      children: [
        if (state == ShelfReadState.ready) ...[
          WText(_writeLine(ready), className: 'text-sm text-fg-muted'),
          // The economics, stated once. It is the cheapest capture path in the app and
          // nothing in the interface would say so.
          WText(
            Lang.get('screens.shelf_photo.credit_note'),
            className: 'text-xs text-fg-muted',
          ),
          MSButton(
            onPressed: ready > 0 && !(_controller?.committing ?? false)
                ? () => unawaited(_submit(context))
                : null,
            disabled: ready == 0,
            // The intent carries the disabled state because the disabled STYLE does not, measured on
            // this repo. A shelf where every region was rejected has nothing to write, and a
            // full-strength button promising six products would be the dead control D60 warns about.
            intent: ready > 0 ? ButtonIntent.primary : ButtonIntent.secondary,
            fullWidth: true,
            className: 'justify-center',
            child: WText(
              (_controller?.committing ?? false)
                  ? Lang.get('screens.shelf_photo.submitting')
                  : plural('screens.shelf_photo.submit', ready, {'count': ready}),
            ),
          ),
        ],
        MSButton(
          // **A failed read retries the READ; anything with no row takes a new photograph.** The
          // distinction is the promise `ai-enrichment.md` makes on a failure: "the photo is kept and
          // no credit was spent", so asking the user to shoot it again would be charging them for
          // our own retry.
          //
          // **It hangs on whether a row EXISTS, not on the state, and that was the defect.** An
          // upload refusal also lands in `failed`, so this button read "Try again" and called
          // `reread()`, which returns on its first line when there is no read. The only way out of
          // that screen did nothing at all, and `_retake` was unreachable because this is the button
          // that reaches it.
          onPressed: _busy
              ? null
              : () => unawaited(_canRetryRead ? _retryRead() : _retake(context)),
          disabled: _busy,
          intent: ButtonIntent.ghost,
          fullWidth: true,
          className: 'justify-center',
          child: WDiv(
            className: 'flex flex-row items-center justify-center gap-2',
            children: [
              const WIcon(ShelfPhotoView._retakeIcon, className: 'size-4'),
              WText(_retakeLabel),
            ],
          ),
        ),
        if (state != ShelfReadState.reading)
          MSButton(
            onPressed: _busy
                ? null
                : () {
                    _controller?.reset();
                    MagicRoute.to('/products/new');
                  },
            disabled: _busy,
            intent: ButtonIntent.ghost,
            fullWidth: true,
            className: 'justify-center',
            child: WDiv(
              className: 'flex flex-row items-center justify-center gap-2',
              children: [
                const WIcon(ShelfPhotoView._manualIcon, className: 'size-4'),
                WText(Lang.get('screens.shelf_photo.manual')),
              ],
            ),
          ),
      ],
    );
  }

  /// What the button is about to write, and what it is leaving behind.
  ///
  /// Two sentences composed rather than one string with two numbers in it, because a single value
  /// can only agree with one count: `4 products will be written, 1 regions were not recognised` was
  /// on screen before this. `barcode_scan_view` composes its own partial line the same way.
  String _writeLine(int ready) {
    final int unresolved = _read.unresolved.length;

    final String written = plural('screens.shelf_photo.will_write', ready, {'count': ready});

    if (unresolved == 0) return written;

    return Lang.get('screens.shelf_photo.will_write_partial', {
      'written': written,
      'unresolved': plural('screens.shelf_photo.unresolved_count', unresolved, {'count': unresolved}),
    });
  }

  /// The photograph the boxes are drawn over.
  ///
  /// The placeholder is what a preview shows and what a resumed read shows: the server keeps its copy
  /// on a private disk with no route serving it, so a read reopened without the local file has no
  /// picture to offer. D60's whole design rests on the picture, which is why that case is drawn as an
  /// absence rather than as an empty box.
  Widget _buildPicture() {
    final Future<Uint8List>? bytes = _photoBytes;

    if (bytes == null) return _buildNoPicture();

    return FutureBuilder<Uint8List>(
      future: bytes,
      builder: (BuildContext context, AsyncSnapshot<Uint8List> snapshot) {
        final Uint8List? data = snapshot.data;

        return data == null
            ? _buildNoPicture()
            : Image.memory(data, fit: BoxFit.cover);
      },
    );
  }

  Widget _buildNoPicture() {
    return const WDiv(
      className: 'flex flex-col items-center justify-center',
      child: WIcon(Icons.photo_outlined, className: 'size-10 text-fg-disabled'),
    );
  }

  /// Asks the user what one region is, and records the answer locally.
  ///
  /// Nothing reaches the server here. D60's accept count is the settled count and the user is allowed
  /// to change their mind about a region before submitting the shelf, so the decision lands in the
  /// controller's own copy and the whole batch goes at once.
  Future<void> _decide(BuildContext context, ShelfCandidate candidate) async {
    final ShelfController? controller = _controller;

    if (controller == null) return;

    final ShelfDecision? decision = await ShelfCandidateSheet.show(
      context,
      candidate: candidate,
      unitCodes: _units,
    );

    if (decision == null || !context.mounted) return;

    if (decision.isRejection) {
      controller.decide(candidate.rejected);

      return;
    }

    // A region nothing could name needs a product before it can be counted. `ShelfCommitter` takes
    // ids only, the same as `ReceiptCommitter`, so this is one request per new product and the
    // backend's own docblock names `stock/receive-batch` as the fix if that ever bites.
    final String? productId = decision.productId ??
        await controller.createProduct(
          name: decision.newProductName!,
          unit: decision.newProductUnit,
        );

    if (productId == null) return;

    // The unit travels with the decision, because a region nothing could name has none of its own:
    // without it the row rendered a quantity with nothing beside it, on the one path where the user
    // had just chosen a unit two taps earlier.
    controller.decide(candidate.accepted(
      productId: productId,
      quantity: decision.quantity,
      unit: decision.newProductUnit,
    ));
  }

  /// Picks a location, then writes the settled regions into it.
  ///
  /// The location is asked once for the whole shelf rather than per region, because a shelf IS one
  /// place: that is the shape `stock/receive-batch` has and the reason the commit endpoint takes a
  /// single `location_id`.
  Future<void> _submit(BuildContext context) async {
    final ShelfController? controller = _controller;

    if (controller == null) return;

    final String? locationId = await MSBottomSheet.show<String>(
      context,
      title: Lang.get('screens.shelf_photo.destination_title'),
      // The sheet is its own widget, so its search field's state belongs to it: a `setState` here
      // while it is open would rebuild the photograph and its boxes behind it.
      // No recents: `stock/recent-receiving-locations` answers where DELIVERIES land, and a shelf
      // read is a count of what is already on that shelf. Offering the receiving bench first would
      // put the likeliest wrong answer at the top of the list.
      body: DestinationSheet(options: _locations, recentIds: const <String>[]),
    );

    if (locationId == null || !context.mounted) return;

    final String? failure = await controller.commit(locationId: locationId);

    if (!context.mounted) return;

    if (failure != null) {
      MagicFeedback.error(Lang.get('screens.shelf_photo.title'), failure);

      return;
    }

    MagicFeedback.success(
      Lang.get('screens.shelf_photo.title'),
      plural('screens.shelf_photo.written', _read.settled.length, {'count': _read.settled.length}),
    );

    controller.reset();
    MagicRoute.to('/products');
  }

  /// Reads the same photograph again, without spending a second upload.
  Future<void> _retryRead() async {
    await _controller?.reread();
  }

  /// Takes another photograph and starts over.
  Future<void> _retake(BuildContext context) async {
    final XFile? photo = await pickPhoto();

    if (photo == null || !context.mounted) return;

    final ShelfController controller = ShelfController.instance..begin(photo);

    setState(() => _photoBytes = photo.readAsBytes());

    unawaited(controller.uploadAndRead());
  }
}
