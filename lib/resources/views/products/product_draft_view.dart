import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart'
    show MSPageScaffold, MSButton, ButtonIntent, MSSkeleton, SkeletonShape;

import '../../../ui/components/draft_field/draft_field.dart';
import '../../../ui/components/section_card/section_card.dart';
import '../../../ui/components/tag/index.dart';
import 'field_editor_sheet.dart';
import 'product_filter_sheet.dart' show FilterOption;
import 'product_fixtures.dart';

/// A product being created: the draft card that fills itself in.
///
/// **Not a blank form.** `ai-enrichment.md` fixed this shape before any of it was
/// built: a draft card appears immediately and its fields populate progressively from
/// the enrichment call, nothing waits on the model, and every field is editable before
/// commit. So the design problem was never "how do you fit thirteen fields on a phone",
/// it was "what does a field look like while it is still arriving".
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
/// ### What the states mean here
///
/// The screen is deliberately shown mid-fill, because that is the state nobody designs
/// and everybody ships. Name is filled (the user typed it), category and brand arrived
/// from the model, the description is still streaming, and SKU came back empty because
/// the model had nothing. Unit, content and shelf life are filled but marked `tahmin`,
/// since D32 infers them and a wrongly inferred unit changes what every quantity in the
/// ledger means.
///
/// **No tracking-mode question** (D30). Every product starts lot-tracked; "Seri
/// numarası ekle" in the saved screen's overflow flips it when the user needs it.
@immutable
class ProductDraftView extends StatelessWidget {
  static const IconData _cameraIcon = Icons.photo_camera_outlined;

  /// Whether the enrichment call is still running.
  ///
  /// Two variants rather than an animation, because both have to be reviewable: the
  /// mid-fill state is what a user actually sees for the first second or two, and the
  /// settled state is what they act on.
  final bool isEnriching;

  /// Creates the [ProductDraftView] mid-enrichment.
  const ProductDraftView({super.key}) : isEnriching = true;

  /// Creates the view after enrichment has settled.
  const ProductDraftView.settled({super.key}) : isEnriching = false;

  /// The product the draft is becoming, for the values the model returned.
  ProductListItem get _source => productFixtures.first;

  @override
  Widget build(BuildContext context) {
    return MSPageScaffold(
      title: Lang.get('screens.product_draft.title'),
      // No subtitle: the brand is one of the fields still arriving, and a page subtitle
      // that appears a second after the page did reads as a layout jump.
      children: [
        _buildIdentity(context),
        _buildMeasure(context),
        _buildFirstStock(context),
        _buildSave(context),
      ],
    );
  }

  /// Opens the one editor every field shares.
  ///
  /// Every call passes the current value as the first quick answer, which is what makes
  /// "I looked and it was right" a single tap. Saving clears the `otomatik` mark whether
  /// or not the value changed (D53); dismissing leaves it, because looking is not
  /// confirming.
  void _edit(
    BuildContext context, {
    required String label,
    String? provenance,
    String? value,
    String? unit,
    FieldEditorKind kind = FieldEditorKind.text,
    List<String> quickAnswers = const <String>[],
    List<String> options = const <String>[],
    String? suggestedOption,
    String? suggestionReason,
    bool isOptional = false,
  }) {
    FieldEditorSheet.show(
      context,
      label: label,
      provenance: provenance,
      value: value,
      unit: unit,
      kind: kind,
      quickAnswers: [?value, ...quickAnswers],
      options: options,
      suggestedOption: suggestedOption,
      suggestionReason: suggestionReason,
      isOptional: isOptional,
    );
  }

  /// Name, photo and what the model made of them.
  ///
  /// The name is the only thing the user typed and the only thing required (D32), so it
  /// leads at page-title weight rather than sitting in a labelled row like the rest.
  Widget _buildIdentity(BuildContext context) {
    return WDiv(
      className: 'flex flex-col gap-3 p-4 rounded-lg bg-surface-container',
      children: [
        WDiv(
          className: 'flex flex-row items-start gap-3',
          children: [
            // The photo is an entry point, not decoration: it is one of the four things
            // enrichment accepts, so an empty slot here is an offer to fill the card.
            WAnchor(
              onTap: () {},
              semanticLabel: Lang.get('screens.product_draft.add_photo'),
              child: WDiv(
                className: '''
                  size-20 rounded-md bg-surface-container-high
                  flex flex-col items-center justify-center gap-1
                ''',
                children: [
                  const WIcon(_cameraIcon, className: 'size-6 text-fg-muted'),
                  WText(Lang.get('screens.product_draft.photo'), className: 'text-xs text-fg-muted'),
                ],
              ),
            ),
            WDiv(
              className: 'flex flex-col gap-2 flex-1 min-w-0',
              children: [
                WText(_source.name, className: 'text-lg font-semibold text-fg'),
                if (isEnriching)
                  const MSSkeleton(shape: SkeletonShape.text, width: 90, height: 20)
                else
                  WDiv(
                    className: 'flex flex-row wrap items-center gap-1',
                    children: [
                      if (_source.categoryLabel != null)
                        Tag(
                          label: _source.categoryLabel!,
                          intent: TagIntent.primary,
                          size: TagSize.sm,
                        ),
                      for (final String tag in _source.tags) Tag(label: tag, size: TagSize.sm),
                    ],
                  ),
              ],
            ),
          ],
        ),
        DraftField(
          label: Lang.get('screens.product_draft.brand'),
          value: _source.brand,
          state: isEnriching ? DraftFieldState.loading : null,
          onTap: () => _edit(
            context,
            label: Lang.get('screens.product_draft.brand'),
            provenance: Lang.get('screens.product_draft.from_photo'),
            value: _source.brand,
          ),
        ),
        DraftField(
          label: Lang.get('screens.product_draft.description'),
          value: isEnriching ? null : _source.description,
          state: isEnriching ? DraftFieldState.loading : null,
          prompt: Lang.get('screens.product_draft.unread'),
          onTap: () => _edit(
            context,
            label: Lang.get('screens.product_draft.description'),
            provenance: Lang.get('screens.product_draft.from_photo'),
            value: _source.description,
            isOptional: true,
          ),
        ),
        // SKU stays empty after enrichment settles, on purpose. It is the tenant's own
        // code and no model can know it, so this is the honest resting state of the
        // unsure variant rather than a transient one.
        DraftField(
          label: 'SKU',
          state: DraftFieldState.unsure,
          prompt: Lang.get('screens.product_draft.optional'),
          // No provenance line and no quick answers: a tenant's own code is the one field
          // no model can guess, so there is nothing to confirm and nothing to offer.
          onTap: () => _edit(context, label: 'SKU', isOptional: true),
        ),
      ],
    );
  }

  /// The three fields D32 infers, each carrying its provisional mark.
  ///
  /// Their own card rather than mixed into identity, because they are the fields that
  /// change what a NUMBER means. Grouping them is what makes "these three were guessed"
  /// a single glance instead of three scattered markers.
  Widget _buildMeasure(BuildContext context) {
    return SectionCard(
      label: Lang.get('screens.product_draft.measure_group'),
      children: [
        DraftField(
          label: Lang.get('screens.product_draft.unit'),
          value: _source.unit,
          unconfirmed: true,
          state: isEnriching ? DraftFieldState.loading : null,
          // Free to change here and only here (D54): a draft has no stock, so nothing is
          // reinterpreted. After the first movement this stops being a field edit.
          onTap: () => _edit(
            context,
            label: Lang.get('screens.product_draft.unit'),
            provenance: Lang.get('screens.product_draft.from_name'),
            value: _source.unit,
            kind: FieldEditorKind.choice,
            options: const ['adet', 'kg', 'gram', 'litre', 'ml', 'paket', 'kutu'],
          ),
        ),
        DraftField(
          label: Lang.get('screens.product_draft.content'),
          value: _source.contentAmount == null
              ? null
              : Lang.get('screens.product_draft.content_value', {'amount': _source.contentAmount!.round(), 'unit': _source.contentUnit}),
          unconfirmed: true,
          state: isEnriching ? DraftFieldState.loading : null,
          prompt: Lang.get('screens.product_draft.optional'),
          onTap: () => _edit(
            context,
            label: Lang.get('screens.product_draft.content'),
            provenance: Lang.get('screens.product_draft.from_name'),
            value: _source.contentAmount?.round().toString(),
            unit: _source.contentUnit,
            kind: FieldEditorKind.number,
            isOptional: true,
          ),
        ),
        DraftField(
          label: Lang.get('screens.product_draft.shelf_life'),
          value: _source.shelfLifeDays == null
              ? null
              : Lang.get('screens.product_draft.shelf_life_value', {'days': _source.shelfLifeDays}),
          unconfirmed: true,
          state: isEnriching ? DraftFieldState.loading : null,
          prompt: Lang.get('screens.product_draft.not_tracked'),
          onTap: () => _edit(
            context,
            label: Lang.get('screens.product_draft.shelf_life'),
            provenance: Lang.get('screens.product_draft.from_category'),
            value: _source.shelfLifeDays?.toString(),
            unit: Lang.get('screens.product_draft.days'),
            kind: FieldEditorKind.number,
            quickAnswers: const ['7', '30', '365'],
            isOptional: true,
          ),
        ),
      ],
    );
  }

  /// D13's grouped card of tap-chips: the first stock entry, all at once.
  ///
  /// **Never as sequential questions.** Three chips in a row that each open an editor,
  /// so a user who only wants to change the location taps once instead of walking a
  /// wizard. The quantity and location arrive suggested, the date derives from the shelf
  /// life above, and each chip says whether its value was guessed.
  ///
  /// The suggestion line carries its own reason and its count, because
  /// `location-assignment.md` makes the count the explanation rather than internal
  /// state: a suggestion the user can argue with is one they will accept.
  Widget _buildFirstStock(BuildContext context) {
    final (String, int)? affinity = suggestLocationFor(_source.categoryId);

    return SectionCard(
      label: Lang.get('screens.product_draft.first_stock_group'),
      children: [
        WDiv(
          className: 'flex flex-row wrap items-center gap-2 py-1',
          children: [
            DraftField(
              label: Lang.get('screens.product_draft.quantity'),
              value: '1 ${_source.unit}',
              layout: DraftFieldLayout.chip,
              onTap: () => _edit(
                context,
                label: Lang.get('screens.product_draft.quantity'),
                value: '1',
                unit: _source.unit,
                kind: FieldEditorKind.number,
                quickAnswers: const ['2', '6', '12'],
              ),
            ),
            DraftField(
              label: Lang.get('screens.product_draft.location'),
              value: affinity == null ? null : resolveLocationPath(affinity.$1),
              unconfirmed: affinity != null,
              layout: DraftFieldLayout.chip,
              state: isEnriching ? DraftFieldState.loading : null,
              onTap: () => _edit(
                context,
                label: Lang.get('screens.product_draft.location'),
                provenance: Lang.get('screens.product_draft.from_history'),
                value: affinity == null ? null : resolveLocationPath(affinity.$1),
                kind: FieldEditorKind.choice,
                options: [for (final FilterOption o in locationOptions) o.fullPath],
                suggestedOption: affinity == null ? null : resolveLocationPath(affinity.$1),
                // The count IS the explanation, here as everywhere else the app suggests
                // a location. Dropping it would make the draft form's picker weaker than
                // the stock sheets' for no reason.
                suggestionReason: affinity == null
                    ? null
                    : Lang.get('screens.product_draft.suggested_count', {'count': affinity.$2}),
              ),
            ),
            DraftField(
              label: Lang.get('screens.product_draft.expiry'),
              value: _source.shelfLifeDays == null ? null : '11 Ağu',
              unconfirmed: true,
              layout: DraftFieldLayout.chip,
              state: isEnriching ? DraftFieldState.loading : null,
              // Offsets rather than a calendar first. A shelf life of five days makes
              // "+5 gün" the answer nine times out of ten, and a date picker for a date
              // the app already computed is three taps to agree with it.
              onTap: () => _edit(
                context,
                label: Lang.get('screens.product_draft.expiry'),
                provenance: Lang.get('screens.product_draft.from_shelf_life'),
                value: '11 Ağu',
                kind: FieldEditorKind.choice,
                options: ['11 Ağu (+5 gün)', '18 Ağu (+12 gün)', Lang.get('screens.product_draft.pick_date'), Lang.get('screens.product_draft.unknown')],
              ),
            ),
          ],
        ),
        if (!isEnriching && affinity != null)
          WText(
            Lang.get('screens.product_draft.location_reason', {'count': affinity.$2}),
            className: 'text-xs text-ai',
          ),
      ],
    );
  }

  /// One button, always enabled.
  ///
  /// D32: a name alone is enough, and the name is already there because typing it is how
  /// the user arrived. So there is no state in which this button should refuse, and per
  /// the measured finding that `MSButton`'s disabled produces no visible change anyway,
  /// a button that refuses invisibly would be worse than one that always works.
  Widget _buildSave(BuildContext context) {
    return WDiv(
      className: 'flex flex-col gap-2 pb-2',
      children: [
        MSButton(
          onPressed: () {},
          fullWidth: true,
          className: 'justify-center',
          child: WText(Lang.get('screens.product_draft.save')),
        ),
        MSButton(
          onPressed: () {},
          intent: ButtonIntent.ghost,
          fullWidth: true,
          className: 'justify-center',
          child: WText(Lang.get('screens.product_draft.cancel')),
        ),
      ],
    );
  }
}
