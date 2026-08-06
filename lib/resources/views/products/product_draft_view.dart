import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart'
    show MSPageScaffold, MSButton, ButtonIntent, MSSkeleton, SkeletonShape;

import '../../../ui/components/draft_field/draft_field.dart';
import '../../../ui/components/section_card/section_card.dart';
import '../../../ui/components/tag/index.dart';
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
      title: 'Yeni ürün',
      // No subtitle: the brand is one of the fields still arriving, and a page subtitle
      // that appears a second after the page did reads as a layout jump.
      children: [_buildIdentity(), _buildMeasure(), _buildFirstStock(), _buildSave(context)],
    );
  }

  /// Name, photo and what the model made of them.
  ///
  /// The name is the only thing the user typed and the only thing required (D32), so it
  /// leads at page-title weight rather than sitting in a labelled row like the rest.
  Widget _buildIdentity() {
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
              semanticLabel: 'Fotoğraf ekle',
              child: WDiv(
                className: '''
                  size-20 rounded-md bg-surface-container-high
                  flex flex-col items-center justify-center gap-1
                ''',
                children: [
                  const WIcon(_cameraIcon, className: 'size-6 text-fg-muted'),
                  WText('Fotoğraf', className: 'text-xs text-fg-muted'),
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
          label: 'Marka',
          value: _source.brand,
          state: isEnriching ? DraftFieldState.loading : null,
          onTap: () {},
        ),
        DraftField(
          label: 'Açıklama',
          value: isEnriching ? null : _source.description,
          state: isEnriching ? DraftFieldState.loading : null,
          prompt: 'fotoğraftan okunamadı',
          onTap: () {},
        ),
        // SKU stays empty after enrichment settles, on purpose. It is the tenant's own
        // code and no model can know it, so this is the honest resting state of the
        // unsure variant rather than a transient one.
        DraftField(
          label: 'SKU',
          state: DraftFieldState.unsure,
          prompt: 'kendi kodun, istersen yaz',
          onTap: () {},
        ),
      ],
    );
  }

  /// The three fields D32 infers, each carrying its provisional mark.
  ///
  /// Their own card rather than mixed into identity, because they are the fields that
  /// change what a NUMBER means. Grouping them is what makes "these three were guessed"
  /// a single glance instead of three scattered markers.
  Widget _buildMeasure() {
    return SectionCard(
      label: 'Ölçü',
      children: [
        DraftField(
          label: 'Birim',
          value: _source.unit,
          unconfirmed: true,
          state: isEnriching ? DraftFieldState.loading : null,
          onTap: () {},
        ),
        DraftField(
          label: 'İçerik',
          value: _source.contentAmount == null
              ? null
              : '${_source.contentAmount!.round()} ${_source.contentUnit}',
          unconfirmed: true,
          state: isEnriching ? DraftFieldState.loading : null,
          prompt: 'ambalajda yazmıyorsa boş bırak',
          onTap: () {},
        ),
        DraftField(
          label: 'Raf ömrü',
          value: _source.shelfLifeDays == null ? null : '${_source.shelfLifeDays} gün',
          unconfirmed: true,
          state: isEnriching ? DraftFieldState.loading : null,
          prompt: 'son kullanma takip edilmeyecek',
          onTap: () {},
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
  Widget _buildFirstStock() {
    final (String, int)? affinity = suggestLocationFor(_source.categoryId);

    return SectionCard(
      label: 'İlk stok',
      children: [
        WDiv(
          className: 'flex flex-row wrap items-center gap-2 py-1',
          children: [
            DraftField(
              label: 'Miktar',
              value: '1 ${_source.unit}',
              layout: DraftFieldLayout.chip,
              onTap: () {},
            ),
            DraftField(
              label: 'Konum',
              value: affinity == null ? null : resolveLocationPath(affinity.$1),
              unconfirmed: affinity != null,
              layout: DraftFieldLayout.chip,
              state: isEnriching ? DraftFieldState.loading : null,
              onTap: () {},
            ),
            DraftField(
              label: 'Son kullanma',
              value: _source.shelfLifeDays == null ? null : '11 Ağu',
              unconfirmed: true,
              layout: DraftFieldLayout.chip,
              state: isEnriching ? DraftFieldState.loading : null,
              onTap: () {},
            ),
          ],
        ),
        if (!isEnriching && affinity != null)
          WText(
            'Konum önerisi: bu kategori buraya ${affinity.$2} kez konuldu',
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
          child: const WText('Kaydet'),
        ),
        MSButton(
          onPressed: () {},
          intent: ButtonIntent.ghost,
          fullWidth: true,
          className: 'justify-center',
          child: const WText('Vazgeç'),
        ),
      ],
    );
  }
}
