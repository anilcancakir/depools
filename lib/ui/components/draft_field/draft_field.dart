import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart' show MSSkeleton, SkeletonShape;

import 'draft_field.recipe.dart';

/// How a draft field is laid out.
enum DraftFieldLayout {
  /// A labelled line inside a card. The default.
  row,

  /// An inline capsule, for D13's grouped tap-chips.
  chip,
}

/// What is known about one field on a draft product card.
enum DraftFieldState {
  /// The enrichment call is still running. A skeleton stands in.
  loading,

  /// The call finished and the model had no answer. This is NOT the same as optional.
  unsure,

  /// There is a value.
  filled,
}

/// **DraftField**
///
/// One field on a product being created, in one of three states: still loading, empty
/// because the model could not tell, or filled.
///
/// **The middle state is the reason this component exists.** `ai-enrichment.md` says
/// uncertainty is null rather than a guess, which is right, and it means the card will
/// have empty fields. An empty field that looks like one the user chose to skip hides
/// the fact that the model gave up, so this one says so and offers itself.
///
/// **No confidence number** (D31). Every consumer product surveyed signals uncertainty
/// with a state rather than a score, and the research says a miscalibrated score
/// actively harms: over-trust in wrong high-confidence answers, under-trust in correct
/// low-confidence ones, with almost no accuracy gain even when calibrated.
///
/// [unconfirmed] is orthogonal to the states. An inferred value is filled AND
/// provisional, and D32 requires the distinction: a unit inferred from a product name
/// decides what every quantity in the ledger means, so it stays visibly an inference
/// until someone accepts it.
///
/// ### Example
///
/// ```dart
/// DraftField(label: 'Marka', value: 'Pınar', onTap: edit)
/// DraftField(label: 'Marka', state: DraftFieldState.loading)
/// DraftField(label: 'SKU', state: DraftFieldState.unsure, onTap: edit)
/// DraftField(label: 'Birim', value: 'adet', unconfirmed: true, onTap: edit)
/// ```
@immutable
class DraftField extends StatelessWidget {
  static const IconData _unsureIcon = Icons.edit_outlined;

  /// The field name, rendered as a micro-caption.
  final String label;

  /// The value, when there is one. Null puts the field in [DraftFieldState.unsure]
  /// unless [state] says otherwise.
  final String? value;

  /// Which state to render. Defaults to filled when [value] is set, unsure otherwise,
  /// so a caller cannot accidentally show a value in a loading skeleton.
  final DraftFieldState? state;

  /// Whether a filled value was inferred rather than confirmed.
  final bool unconfirmed;

  /// The prompt shown in the unsure state. Defaults to a generic invitation.
  final String? prompt;

  /// Which layout to render.
  final DraftFieldLayout layout;

  /// Called when the field is tapped to edit it.
  final VoidCallback? onTap;

  /// Creates a [DraftField].
  const DraftField({
    super.key,
    required this.label,
    this.value,
    this.state,
    this.unconfirmed = false,
    this.prompt,
    this.layout = DraftFieldLayout.row,
    this.onTap,
  });

  /// The state to render, derived when the caller did not force one.
  DraftFieldState get _state =>
      state ?? (value == null ? DraftFieldState.unsure : DraftFieldState.filled);

  @override
  Widget build(BuildContext context) {
    final slots = draftFieldRecipe()();

    return WAnchor(
      // Loading is not tappable: there is nothing to edit yet, and offering the tap
      // would let a user open an editor that a streaming value then overwrites.
      onTap: _state == DraftFieldState.loading ? null : onTap,
      semanticLabel: switch (_state) {
        DraftFieldState.loading => '$label yükleniyor',
        DraftFieldState.unsure => '$label boş, doldurmak için dokun',
        DraftFieldState.filled => '$label: $value${unconfirmed ? ', doğrulanmadı' : ''}',
      },
      child: layout == DraftFieldLayout.chip ? _buildChip(slots) : _buildRow(slots),
    );
  }

  /// The capsule layout: value alone when there is one, the label when there is not.
  Widget _buildChip(Map<String, String> slots) {
    return WDiv(
      className: slots['chipRoot'],
      children: [
        switch (_state) {
          DraftFieldState.loading => const MSSkeleton(
            shape: SkeletonShape.text,
            width: 56,
            height: 14,
          ),
          DraftFieldState.unsure => WDiv(
            className: 'flex flex-row items-center gap-1.5 axis-min',
            children: [
              WIcon(_unsureIcon, className: 'size-3.5 text-ai'),
              WText(prompt ?? '$label seç', className: slots['chipPrompt']),
            ],
          ),
          DraftFieldState.filled => WText(value!, className: slots['chipValue']),
        },
        if (_state == DraftFieldState.filled && unconfirmed)
          WText('tahmin', className: slots['chipMarker']),
      ],
    );
  }

  /// The labelled-line layout.
  Widget _buildRow(Map<String, String> slots) {
    return WDiv(
      className: slots['root'],
      children: [
        WText(label, className: slots['label']),
        switch (_state) {
          DraftFieldState.loading => const MSSkeleton(
            shape: SkeletonShape.text,
            width: 140,
            height: 16,
          ),
          DraftFieldState.unsure => WDiv(
            className: 'flex flex-row items-center gap-1.5',
            children: [
              WIcon(_unsureIcon, className: 'size-3.5 text-ai'),
              WText(prompt ?? 'modelden gelmedi, sen yaz', className: slots['prompt']),
            ],
          ),
          DraftFieldState.filled => WDiv(
            className: 'flex flex-row items-baseline gap-2',
            children: [
              WText(value!, className: slots['value']),
              // The marker says the value is provisional, not that it is wrong.
              // "tahmin" rather than a warning glyph: the app guessed, it worked, and
              // the user can leave it alone or fix it.
              if (unconfirmed) WText('tahmin', className: slots['marker']),
            ],
          ),
        },
      ],
    );
  }
}
