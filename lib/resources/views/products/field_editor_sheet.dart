import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart'
    show MSBottomSheet, MSButton, ButtonIntent, MSInput;

import '../../../ui/components/choice_chip/choice_chip.dart';
import '../../../ui/components/option_row/option_row.dart';

/// What kind of control a field needs.
enum FieldEditorKind {
  /// Free text: a brand, a description, a tenant's own code.
  text,

  /// A number, optionally with a unit beside it.
  number,

  /// One of a known set: a unit, a location, a date offset.
  choice,
}

/// Editing one field of a draft product.
///
/// **One sheet for every field, in three shapes.** A brand, a shelf life and a location are
/// different data and the same interaction: say what the field is, offer the answers worth
/// one tap, and let the user type if none of them fit. Nine bespoke editors would be nine
/// things to learn on a screen whose whole point is that it fills itself in.
///
/// ### The three parts, in this order
///
/// **What it is.** The sheet's own title and a line saying where the current value came
/// from. `Fotoğraftan okundu` and `İsteğe bağlı` are different situations and the user
/// cannot tell them apart from the field alone.
///
/// **The quick answers.** Chips, and the first one is always the value already in the field
/// when there is one. That is what makes "I looked and it was right" cost a single tap,
/// which matters because most inferred values are right and the draft screen's job is to
/// make agreeing cheaper than typing.
///
/// **The control.** A text box, a number box with its unit, or a list of options. Present
/// even when the chips cover the common cases, because a chip set that cannot be escaped is
/// a wizard.
///
/// ### Editing clears the mark, and so does confirming
///
/// D53. A value the app inferred carries an `otomatik` mark. Saving from this sheet removes
/// it whether or not the value changed, because a value the user has looked at and kept is
/// no longer a guess. Dismissing without saving leaves it, because looking is not
/// confirming. So the marks decay as the draft is reviewed instead of staying as permanent
/// noise, and the screen has a natural finish line.
@immutable
class FieldEditorSheet extends StatefulWidget {
  /// The field's already-localised name, used as the sheet title.
  final String label;

  /// Where the current value came from, already localised. Null when there is nothing to
  /// say about it.
  final String? provenance;

  /// The current value, if any.
  final String? value;

  /// The unit shown beside a number, for example `ml` or `gün`.
  final String? unit;

  /// What kind of control to show.
  final FieldEditorKind kind;

  /// The one-tap answers, in order. The current value belongs first when there is one.
  final List<String> quickAnswers;

  /// The options for [FieldEditorKind.choice].
  final List<String> options;

  /// The option the app would pick, if any.
  final String? suggestedOption;

  /// Why [suggestedOption] is suggested, already localised. Carried through to the option
  /// row so the draft form's picker explains itself the way the stock sheets' pickers do:
  /// a suggestion the user can disagree with is one they will accept.
  final String? suggestionReason;

  /// Whether the field may be left empty, which decides whether a clear action is offered.
  final bool isOptional;

  /// Creates a [FieldEditorSheet].
  const FieldEditorSheet({
    super.key,
    required this.label,
    this.provenance,
    this.value,
    this.unit,
    this.kind = FieldEditorKind.text,
    this.quickAnswers = const <String>[],
    this.options = const <String>[],
    this.suggestedOption,
    this.suggestionReason,
    this.isOptional = false,
  });

  /// Opens the editor for one field.
  static Future<String?> show(
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
    return MSBottomSheet.show<String>(
      context,
      title: label,
      description: provenance,
      body: FieldEditorSheet(
        label: label,
        provenance: provenance,
        value: value,
        unit: unit,
        kind: kind,
        quickAnswers: quickAnswers,
        options: options,
        suggestedOption: suggestedOption,
        suggestionReason: suggestionReason,
        isOptional: isOptional,
      ),
    );
  }

  @override
  State<FieldEditorSheet> createState() => _FieldEditorSheetState();
}

class _FieldEditorSheetState extends State<FieldEditorSheet> {
  late String? _value = widget.value;

  @override
  Widget build(BuildContext context) {
    return WDiv(
      className: 'flex flex-col gap-5',
      children: [
        // No chips on a choice field. The options list IS the set of one-tap answers, and
        // a chip row repeating the first option was pure duplication: the same word twice,
        // eight pixels apart, both selected.
        if (widget.kind != FieldEditorKind.choice && widget.quickAnswers.isNotEmpty)
          _buildQuickAnswers(),
        _buildControl(),
        _buildActions(),
      ],
    );
  }

  /// The answers worth one tap. The current value leads when there is one.
  Widget _buildQuickAnswers() {
    return _group(
      'Hazır cevaplar',
      WDiv(
        className: 'flex flex-row wrap items-center gap-2',
        children: [
          for (final String answer in widget.quickAnswers)
            ChoiceChip(
              // The unit rides on the LABEL and not on the value. A row of naked numbers
              // reading "5 · 7 · 30 · 365" is cryptic at a glance even under a title that
              // names the field, and putting the unit into the value would store "7 gün"
              // in a number field.
              label: _labelFor(answer),
              isSuggested: answer == _value,
              semanticLabel: answer == _value
                  ? '${widget.label}: ${_labelFor(answer)}, seçili'
                  : '${widget.label} alanını ${_labelFor(answer)} yap',
              onTap: () => setState(() => _value = answer),
            ),
        ],
      ),
    );
  }

  /// The escape hatch from the chips, which is what stops this being a wizard.
  Widget _buildControl() {
    switch (widget.kind) {
      case FieldEditorKind.text:
        return _group(
          'Serbest giriş',
          MSInput(
            className: 'bg-surface-container',
            value: _value ?? '',
            placeholder: widget.label,
            onChanged: _set,
          ),
        );
      case FieldEditorKind.number:
        return _group(
          'Serbest giriş',
          WDiv(
            className: 'flex flex-row items-center gap-2',
            children: [
              WDiv(
                className: 'flex-1 min-w-0',
                child: MSInput(
                  className: 'bg-surface-container',
                  value: _value ?? '',
                  placeholder: '0',
                  type: InputType.number,
                  onChanged: _set,
                ),
              ),
              // The unit sits beside the box rather than inside it, because it is not
              // editable here: changing what a number MEANS is a different decision from
              // changing the number, and D54 keeps them apart.
              if (widget.unit != null)
                WText(widget.unit!, className: 'text-sm text-fg-muted axis-min'),
            ],
          ),
        );
      case FieldEditorKind.choice:
        return _group(
          'Seçenekler',
          WDiv(
            className: 'flex flex-col gap-1',
            children: [
              for (final String option in widget.options)
                OptionRow(
                  label: option,
                  suggestionReason: option == widget.suggestedOption
                      ? widget.suggestionReason
                      : null,
                  isSelected: option == _value,
                  semanticLabel: '${widget.label} alanını $option yap',
                  onTap: () => setState(() => _value = option),
                ),
            ],
          ),
        );
    }
  }

  /// Save, and for an optional field an explicit way to empty it.
  ///
  /// **Save is always live.** There is no state in which this sheet should refuse: an empty
  /// value is a real answer for an optional field, and for a required one the field already
  /// had a value or the draft would not have saved. A button that refuses invisibly would
  /// be worse than one that always works, which is the measured position on `MSButton`'s
  /// disabled state.
  Widget _buildActions() {
    return WDiv(
      className: 'flex flex-col gap-2',
      children: [
        // Saying what saving DOES to the mark, because the mark disappearing is otherwise
        // a surprise: the user changed nothing and the `otomatik` label went away.
        if (widget.provenance != null)
          WText('Kaydedildiğinde otomatik işareti kalkar', className: 'text-xs text-fg-muted'),
        MSButton(
          onPressed: () => Navigator.of(context).pop(_value),
          fullWidth: true,
          className: 'justify-center',
          child: const WText('Kaydet'),
        ),
        if (widget.isOptional)
          MSButton(
            onPressed: () => Navigator.of(context).pop(''),
            intent: ButtonIntent.ghost,
            fullWidth: true,
            className: 'justify-center',
            child: const WText('Alanı boşalt'),
          ),
      ],
    );
  }

  /// A number chip shows its unit; a text or choice chip is already self-describing.
  String _labelFor(String answer) => widget.kind == FieldEditorKind.number && widget.unit != null
      ? '$answer ${widget.unit}'
      : answer;

  void _set(String next) => setState(() => _value = next.isEmpty ? null : next);

  Widget _group(String label, Widget control) {
    return WDiv(
      className: 'flex flex-col gap-2',
      children: [
        WText(label, className: 'text-xs font-medium uppercase tracking-wide text-fg-muted'),
        control,
      ],
    );
  }
}
