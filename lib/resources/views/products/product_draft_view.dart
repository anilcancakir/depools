import 'dart:async';

import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart'
    show MSPageScaffold, MSButton, ButtonIntent, MSSkeleton, SkeletonShape, MSEmptyState;

import '../../../app/controllers/product_draft_controller.dart';
import '../../../app/models/product_draft.dart';
import '../../../app/models/scan_entry.dart';
import '../../../app/support/unit_label.dart';
import '../../../ui/components/draft_field/draft_field.dart';
import '../../../ui/components/section_card/section_card.dart';
import '../../../ui/components/tag/index.dart';
import 'field_editor_sheet.dart';

/// A product being created from a photograph: the draft card that fills itself in.
///
/// **Not a blank form.** `ai-enrichment.md` fixed this shape before any of it was
/// built: a draft card appears immediately and its fields populate from the enrichment
/// call, nothing waits on the model, and every field is editable before commit. So the
/// design problem was never "how do you fit thirteen fields on a phone", it was "what
/// does a field look like while it is still arriving".
///
/// ### Why this is its own view and not a mode on ProductShowView
///
/// D33 says creation IS the detail screen in draft state, and that is still the intent:
/// the two share `SectionCard`, the identity block, the geometry and the reading order.
/// But putting the draft mode INSIDE `ProductShowView` would have given that screen
/// three live combinations at once (draft or saved, times lot or serial tracking), and
/// this session's record on that is unambiguous: four lot-shaped assumptions broke the
/// serial path, and every one of them was invisible until both paths had a fixture and
/// a preview. A third axis would have tripled that debt in one commit.
///
/// So the draft is a separate view that reuses the same components, and merging the two
/// is a deliberate later step with the combinations exercised, rather than a side effect
/// of this one. The cost is honest and named: the identity block exists in two places
/// until then, and a change to it has to be made twice.
///
/// ### The first-stock card is not here yet, and it was drawn
///
/// D13's grouped tap-chips (quantity, location, expiry) lived on this screen while it was
/// a fixture, and they went when it was wired: they need `stock/receive`, a real location
/// tree and a date the app computes, none of which this slice touches. An inert card on a
/// live screen is the exact failure the receipt slice already cost us, where a tap
/// answered 200 and redrew the same thing. Saving lands on the product's own screen,
/// whose stock-in sheet already writes to the ledger, so nothing is unreachable in the
/// meantime.
///
/// ### What the states mean here
///
/// Name, brand and description arrive from the read; SKU never does, because it is the
/// tenant's own code and no model can know it. Unit is marked `otomatik` until the user
/// opens it, since D32 infers it and a wrongly inferred unit changes what every quantity
/// in the ledger means.
///
/// **No tracking-mode question** (D30). Every product starts lot-tracked; "Seri
/// numarası ekle" in the saved screen's overflow flips it when the user needs it.
@immutable
class ProductDraftView extends StatefulWidget {
  static const IconData _cameraIcon = Icons.photo_camera_outlined;

  /// A draft supplied by the caller, which is how the preview catalog stays offline.
  ///
  /// Null means "read [ProductDraftController]", which is what the route does. The state class
  /// only touches the controller when this is null, so a preview never instantiates it and never
  /// issues a request. Same contract, different source: this is the type the endpoint returns, so
  /// it cannot drift from the API the way a hand-built fixture would.
  final ProductDraft? draft;

  /// Whether to draw the read as still in flight. Only consulted alongside [draft].
  final bool isEnriching;

  /// Creates the [ProductDraftView], reading from [ProductDraftController].
  const ProductDraftView({super.key}) : draft = null, isEnriching = false;

  /// Creates the view over a supplied draft, for the catalog.
  const ProductDraftView.preview(
    ProductDraft this.draft, {
    super.key,
    this.isEnriching = false,
  });

  @override
  State<ProductDraftView> createState() => _ProductDraftViewState();
}

class _ProductDraftViewState extends State<ProductDraftView> {
  ProductDraftController? _controller;

  /// The photograph's bytes, read once.
  ///
  /// Held rather than re-read in `build`, because a `FutureBuilder` handed a fresh future on every
  /// rebuild re-reads the file on every keystroke in an editor sheet.
  Future<Uint8List>? _photoBytes;

  @override
  void initState() {
    super.initState();

    // The capture calls `begin` and `read` before navigating, so there is nothing to start here.
    // What this needs is to hear about the answer when it lands.
    if (widget.draft == null) {
      final ProductDraftController controller = ProductDraftController.instance
        ..addListener(_onControllerChanged);

      _controller = controller;
      _photoBytes = controller.photo?.readAsBytes();
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  ProductDraft? get _draft => widget.draft ?? _controller?.draft;

  bool get _isEnriching => widget.draft != null
      ? widget.isEnriching
      : (_controller?.reading ?? false);

  @override
  Widget build(BuildContext context) {
    final ProductDraft? draft = _draft;

    return MSPageScaffold(
      title: Lang.get('screens.product_draft.title'),
      // No subtitle: the brand is one of the fields still arriving, and a page subtitle
      // that appears a second after the page did reads as a layout jump.
      children: draft == null
          ? [_buildNoPhoto()]
          : [
              ?_buildNotice(draft),
              _buildIdentity(context, draft),
              _buildMeasure(context, draft),
              _buildSave(context, draft),
            ],
    );
  }

  /// What `/draft` shows when it is opened without a photograph behind it.
  ///
  /// Reachable by typing the url or by a reload, and the honest answer is not an empty card: this
  /// screen exists for a photograph, and the app already has a screen for typing a product in.
  Widget _buildNoPhoto() {
    return MSEmptyState(
      title: Lang.get('screens.product_draft.no_photo'),
      description: Lang.get('screens.product_draft.no_photo_note'),
      action: MSButton(
        onPressed: () => MagicRoute.to('/products/new'),
        child: WText(Lang.get('screens.product_draft.type_instead')),
      ),
    );
  }

  /// The line above the card explaining a read that did not produce one.
  ///
  /// **Two sentences rather than one, because the two states need different answers from the
  /// user.** Out of credits is something they can act on; unreadable means try another photograph
  /// or type it. The receipt slice shipped a screen that could not tell them apart and it looked
  /// like a tap doing nothing.
  ///
  /// Nothing is shown for a successful read, including a cached one: "we already knew this" is not
  /// news to somebody looking at a filled card, and a banner on the happy path is noise on every
  /// single capture.
  Widget? _buildNotice(ProductDraft draft) {
    if (_isEnriching || draft.recognised) return null;

    final String message = draft.outcome == 'no_credit'
        ? Lang.get('screens.product_draft.no_credit')
        : Lang.get('screens.product_draft.unreadable');

    return WDiv(
      className: 'flex flex-row items-start gap-2 p-3 rounded-md bg-surface-container',
      children: [
        const WIcon(Icons.info_outline, className: 'size-4 shrink-0 text-fg-muted'),
        WText(message, className: 'text-sm text-fg-muted flex-1 min-w-0'),
      ],
    );
  }

  /// Opens the one editor every field shares.
  ///
  /// Every call passes the current value as the first quick answer, which is what makes
  /// "I looked and it was right" a single tap. Saving clears the `otomatik` mark whether
  /// or not the value changed (D53); dismissing leaves it, because looking is not
  /// confirming.
  Future<void> _edit(
    BuildContext context, {
    required String field,
    required String label,
    String? provenance,
    String? value,
    String? unit,
    FieldEditorKind kind = FieldEditorKind.text,
    List<String> quickAnswers = const <String>[],
    List<String> options = const <String>[],
    bool isOptional = false,
    String? Function(String)? decode,
  }) async {
    final String? answer = await FieldEditorSheet.show(
      context,
      label: label,
      provenance: provenance,
      value: value,
      unit: unit,
      kind: kind,
      quickAnswers: [?value, ...quickAnswers],
      options: options,
      isOptional: isOptional,
    );

    // Null is a dismissal rather than an empty answer: the sheet returns the string it holds when
    // it is saved, and clearing a field sends an empty one. So this branch is what makes "looking
    // is not confirming" true, and swapping it for `?? ''` would clear the mark on a swipe down.
    if (answer == null) return;

    if (answer.isEmpty) {
      _controller?.edit(field, null);

      return;
    }

    // **The unit is the one field whose editor shows something other than what it stores.** The
    // sheet's choice kind is a list of strings in and one string out, so a picker offering `C62`
    // would put a Rec 20 code in front of a person and one offering `adet` would send that word to
    // a column that holds codes. `decode` is the seam between the two.
    _controller?.edit(field, decode == null ? answer : decode(answer));
  }

  /// Name, photo and what the model made of them.
  ///
  /// The name is the only required field (D32), so it leads at page-title weight rather
  /// than sitting in a labelled row like the rest.
  Widget _buildIdentity(BuildContext context, ProductDraft draft) {
    return WDiv(
      className: 'flex flex-col gap-3 p-4 rounded-lg bg-surface-container',
      children: [
        WDiv(
          className: 'flex flex-row items-start gap-3',
          children: [
            _buildPhoto(),
            WDiv(
              className: 'flex flex-col gap-2 flex-1 min-w-0',
              children: [
                WAnchor(
                  onTap: () => _edit(
                    context,
                    field: 'name',
                    label: Lang.get('screens.product_draft.name'),
                    provenance: Lang.get('screens.product_draft.from_photo'),
                    value: draft.name,
                  ),
                  semanticLabel: Lang.get('screens.product_draft.name'),
                  // **Muted when there is nothing there, because otherwise the LABEL reads as the
                  // value.** At full title weight "Product name" looks like a product called that,
                  // which is worse than an empty line: it is a wrong answer rather than a missing
                  // one. Seen on the failed-read preview, where it is the normal state.
                  child: WText(
                    draft.name ?? Lang.get('screens.product_draft.name'),
                    className: draft.name == null
                        ? 'text-lg font-semibold text-fg-muted'
                        : 'text-lg font-semibold text-fg',
                  ),
                ),
                if (_isEnriching)
                  const MSSkeleton(shape: SkeletonShape.text, width: 90, height: 20)
                else if (draft.categoryLabel != null)
                  WDiv(
                    className: 'flex flex-row wrap items-center gap-1',
                    children: [
                      Tag(
                        label: draft.categoryLabel!,
                        intent: TagIntent.primary,
                        size: TagSize.sm,
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
        DraftField(
          label: Lang.get('screens.product_draft.brand'),
          value: draft.brand,
          unconfirmed: draft.isUnconfirmed('brand'),
          state: _isEnriching ? DraftFieldState.loading : null,
          onTap: () => _edit(
            context,
            field: 'brand',
            label: Lang.get('screens.product_draft.brand'),
            provenance: Lang.get('screens.product_draft.from_photo'),
            value: draft.brand,
          ),
        ),
        DraftField(
          label: Lang.get('screens.product_draft.description'),
          value: _isEnriching ? null : draft.description,
          unconfirmed: draft.isUnconfirmed('description'),
          state: _isEnriching ? DraftFieldState.loading : null,
          prompt: Lang.get('screens.product_draft.unread'),
          onTap: () => _edit(
            context,
            field: 'description',
            label: Lang.get('screens.product_draft.description'),
            provenance: Lang.get('screens.product_draft.from_photo'),
            value: draft.description,
            isOptional: true,
          ),
        ),
        // SKU stays empty after enrichment settles, on purpose. It is the tenant's own
        // code and no model can know it, so this is the honest resting state of the
        // unsure variant rather than a transient one.
        DraftField(
          label: 'SKU',
          value: draft.sku,
          state: draft.sku == null ? DraftFieldState.unsure : null,
          prompt: Lang.get('screens.product_draft.optional'),
          // No provenance line and no quick answers: a tenant's own code is the one field
          // no model can guess, so there is nothing to confirm and nothing to offer.
          onTap: () => _edit(
            context,
            field: 'sku',
            label: 'SKU',
            value: draft.sku,
            isOptional: true,
          ),
        ),
      ],
    );
  }

  /// The photograph the card was read from, or the slot offering one.
  ///
  /// The picture is an entry point rather than decoration: it is one of the four things
  /// enrichment accepts. Once a photograph is in hand it is also the answer to "is the app
  /// looking at what I am looking at", which is the question a wrong brand raises first.
  Widget _buildPhoto() {
    final Future<Uint8List>? bytes = _photoBytes;

    if (bytes != null) {
      return WDiv(
        className: 'size-20 shrink-0 rounded-md overflow-hidden bg-surface-container-high',
        child: FutureBuilder<Uint8List>(
          future: bytes,
          builder: (BuildContext context, AsyncSnapshot<Uint8List> snapshot) {
            final Uint8List? data = snapshot.data;

            // The empty slot is the placeholder while the read is in flight, so the box never
            // changes size and the card cannot jump under the user's thumb.
            return data == null
                ? _buildEmptyPhoto()
                : Image.memory(data, fit: BoxFit.cover, width: 80, height: 80);
          },
        ),
      );
    }

    return _buildEmptyPhoto();
  }

  /// The slot with no photograph in it.
  ///
  /// **`Image.memory` rather than `Image.file`, and that is the platform rule rather than a
  /// preference.** `dart:io` does not exist on web, and `DESIGN.md` allows the INSTRUMENT to differ
  /// per platform but not the feature: reading the bytes works everywhere `image_picker` does, so
  /// one path covers all three instead of a conditional import covering two.
  Widget _buildEmptyPhoto() {
    return WDiv(
      // **`shrink-0`, and it was missing.** Measured at a narrow width: without it the photo box
      // competed with the name column for space and the name wrapped one CHARACTER per line, with
      // a 134px overflow beside it. `flex-1 min-w-0` on the shrinkable child needs `shrink-0` on
      // the one that keeps its width; design.md names the pair and only half of it was here.
      className: '''
        size-20 shrink-0 rounded-md bg-surface-container-high
        flex flex-col items-center justify-center gap-1
      ''',
      children: [
        const WIcon(ProductDraftView._cameraIcon, className: 'size-6 text-fg-muted'),
        WText(Lang.get('screens.product_draft.photo'), className: 'text-xs text-fg-muted'),
      ],
    );
  }

  /// The fields D32 infers, each carrying its provisional mark.
  ///
  /// Their own card rather than mixed into identity, because they are the fields that
  /// change what a NUMBER means. Grouping them is what makes "these were guessed" a
  /// single glance instead of scattered markers.
  ///
  /// **Contents is absent, and it was drawn.** `content_amount` and `content_unit` are a PAIR the
  /// database enforces as one (`CHECK ((content_amount IS NULL) = (content_unit IS NULL))`), and
  /// the shared editor sheet returns one string: a user who filled the amount would have sent a
  /// half-pair and got `SQLSTATE 23514` for it. Nothing in this slice produces a content unit
  /// either, so the field could only ever have been a way to break the save. It returns with an
  /// editor that takes both halves.
  Widget _buildMeasure(BuildContext context, ProductDraft draft) {
    return SectionCard(
      label: Lang.get('screens.product_draft.measure_group'),
      children: [
        DraftField(
          label: Lang.get('screens.product_draft.unit'),
          value: draft.unit == null ? null : unitLabel(draft.unit!, 1),
          unconfirmed: draft.isUnconfirmed('unit'),
          state: _isEnriching ? DraftFieldState.loading : null,
          prompt: Lang.get('screens.product_draft.optional'),
          // Free to change here and only here (D54): a draft has no stock, so nothing is
          // reinterpreted. After the first movement this stops being a field edit.
          onTap: () {
            final List<String> codes =
                _controller?.units ?? const <String>[ScanEntry.defaultUnit];
            final Map<String, String> byLabel = <String, String>{
              for (final String code in codes) unitLabel(code, 1): code,
            };

            unawaited(_edit(
              context,
              field: 'unit',
              label: Lang.get('screens.product_draft.unit'),
              // **Not `from_photo`, because it is often not from the photograph.** The reader takes
              // the model's word when there is one and the category's own default when there is
              // not, and the response does not say which. One true sentence covering both beats a
              // specific one that is wrong whenever the greengrocer's kilogram came from the
              // taxonomy rather than off a label.
              provenance: Lang.get('screens.product_draft.inferred'),
              value: draft.unit == null ? null : unitLabel(draft.unit!, 1),
              kind: FieldEditorKind.choice,
              options: byLabel.keys.toList(),
              // A label the map does not carry can only be one the user typed into a picker that
              // does not accept typing, so falling back to it would store a word as a code. Null
              // leaves the field empty and the team default answers instead.
              decode: (String label) => byLabel[label],
            ));
          },
        ),
        DraftField(
          label: Lang.get('screens.product_draft.shelf_life'),
          value: draft.shelfLifeDays == null
              ? null
              : Lang.get('screens.product_draft.shelf_life_value', {'days': draft.shelfLifeDays}),
          state: _isEnriching ? DraftFieldState.loading : null,
          prompt: Lang.get('screens.product_draft.not_tracked'),
          onTap: () => _edit(
            context,
            field: 'shelf_life',
            label: Lang.get('screens.product_draft.shelf_life'),
            value: draft.shelfLifeDays?.toString(),
            unit: Lang.get('screens.product_draft.days'),
            kind: FieldEditorKind.number,
            quickAnswers: const ['7', '30', '365'],
            isOptional: true,
          ),
        ),
      ],
    );
  }

  /// One button, disabled only while the name is missing or a save is in flight.
  ///
  /// D32: a name alone is enough. It can be missing here in a way the fixture could not
  /// express, because a read that recognised nothing leaves it empty and the user has to
  /// type one before there is anything to save.
  Widget _buildSave(BuildContext context, ProductDraft draft) {
    final bool saving = _controller?.saving ?? false;
    final bool ready = (draft.name ?? '').isNotEmpty && !saving;

    return WDiv(
      className: 'flex flex-col gap-2 pb-2',
      children: [
        ?_buildError(),
        MSButton(
          onPressed: ready ? () => _save(context) : null,
          disabled: !ready,
          // **The intent carries the disabled state, because the disabled STYLE does not.**
          // Measured on this repo: `MSButton`'s disabled produces no visible change on the primary
          // intent, so a card with no name yet showed a full-strength Save that answered nothing.
          // A dead control that looks live is the anti-pattern; receding to the secondary fill is
          // the caller-side way to say so without touching the shared component.
          intent: ready ? ButtonIntent.primary : ButtonIntent.secondary,
          fullWidth: true,
          className: 'justify-center',
          child: WText(
            saving
                ? Lang.get('screens.product_draft.saving')
                : Lang.get('screens.product_draft.save'),
          ),
        ),
        MSButton(
          onPressed: () {
            _controller?.reset();
            MagicRoute.back();
          },
          intent: ButtonIntent.ghost,
          fullWidth: true,
          className: 'justify-center',
          child: WText(Lang.get('screens.product_draft.cancel')),
        ),
      ],
    );
  }

  Widget? _buildError() {
    final String? error = _controller?.error;

    if (error == null) return null;

    // **`text-destructive` does not exist and drops silently**, the same trap DESIGN.md records for
    // `text-accent`: `design:sync` emits `bg-destructive` and `text-on-destructive` and no text
    // alias. `expired` IS destructive in this palette, by DESIGN.md's own words, and the status
    // families are where tinted text lives.
    return WText(error, className: 'text-sm text-expired');
  }

  /// Write the product, then land on it.
  ///
  /// The product's own screen rather than back to wherever the capture started, for the same
  /// reason `ProductFormView` goes there: the next thing a person does with a product they just
  /// created is put stock in it, and that sheet lives on that screen.
  Future<void> _save(BuildContext context) async {
    final String? id = await _controller?.save();

    if (id == null || !context.mounted) return;

    _controller?.reset();

    MagicRoute.to('/products/${Uri.encodeComponent(id)}');
  }
}
