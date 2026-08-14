import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart' show MSButton, ButtonIntent, MSInput;

/// A unit a tenant wants to add to their own vocabulary.
@immutable
class UnitDraft {
  /// The short code, which the server folds to upper case so one word cannot become three rows.
  final String code;

  /// The tenant's own word for it, kept exactly as typed.
  final String name;

  /// Creates a [UnitDraft].
  const UnitDraft({required this.code, required this.name});
}

/// Registering a unit the standard does not name.
///
/// **The one deliberate way out of a closed vocabulary.** The nineteen seeded UN/ECE codes cover a lot
/// and not everything, and `units.team_id` exists precisely so a tenant who counts in something else can
/// say so ONCE rather than typing it per product. That "once" is the whole difference from the free text
/// this replaced: a typo used to become a unit, and now it becomes a row somebody chose to create.
///
/// ### Two fields, and why the code is not derived from the name
///
/// The code is the identifier and the name is the word. Deriving one from the other looks tidy and
/// breaks immediately: `Yarım kasa` would fold to `YARıM KASA`, and a code is compared against the
/// standard's own (`CT`, `CS`), so it has to be short and stable. Asking for both keeps the tenant in
/// control of the thing that gets compared.
///
/// ### The ratio is NOT asked here
///
/// "One case is twelve pieces" is a real thing to want to say, and the endpoint accepts it, but it is
/// not asked at the moment somebody is halfway through creating a product: `product_units` is where a
/// per-product ratio belongs, and a shared ratio is a second decision. The sheet stays two fields so it
/// costs a few seconds rather than a paragraph.
@immutable
class UnitDraftSheet extends StatefulWidget {
  /// Creates the [UnitDraftSheet].
  const UnitDraftSheet({super.key});

  @override
  State<UnitDraftSheet> createState() => _UnitDraftSheetState();
}

class _UnitDraftSheetState extends State<UnitDraftSheet> {
  final TextEditingController _code = TextEditingController();
  final TextEditingController _name = TextEditingController();

  /// Which field is empty, so the refusal names it rather than disabling a button silently.
  String? _missing;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final String code = _code.text.trim();
    final String name = _name.text.trim();

    if (code.isEmpty || name.isEmpty) {
      setState(() => _missing = code.isEmpty ? 'code' : 'name');

      return;
    }

    Navigator.of(context).pop(UnitDraft(code: code, name: name));
  }

  @override
  Widget build(BuildContext context) {
    return WDiv(
      className: 'flex flex-col gap-4',
      children: [
        WText(
          Lang.get('components.unit_draft.note'),
          className: 'text-xs text-fg-muted',
        ),
        _field(
          Lang.get('components.unit_draft.code_label'),
          Lang.get('components.unit_draft.code_placeholder'),
          _code,
          'code',
        ),
        _field(
          Lang.get('components.unit_draft.name_label'),
          Lang.get('components.unit_draft.name_placeholder'),
          _name,
          'name',
        ),
        MSButton(
          onPressed: _save,
          fullWidth: true,
          className: 'justify-center',
          child: WText(Lang.get('components.unit_draft.save')),
        ),
        MSButton(
          onPressed: () => Navigator.of(context).pop(),
          intent: ButtonIntent.ghost,
          fullWidth: true,
          className: 'justify-center',
          child: WText(Lang.get('components.unit_draft.cancel')),
        ),
      ],
    );
  }

  /// One labelled field, with its own complaint underneath.
  Widget _field(String label, String placeholder, TextEditingController controller, String key) {
    return WDiv(
      className: 'flex flex-col gap-1',
      children: [
        WText(label, className: 'text-xs text-fg-muted'),
        MSInput(
          className: 'bg-surface-container px-3 py-3.5',
          placeholder: placeholder,
          controller: controller,
          // Cleared on the first keystroke, because the complaint is about an empty field and it stops
          // being true the moment they type.
          onChanged: (String _) {
            if (_missing == key) setState(() => _missing = null);
          },
          onSubmitted: (String _) => _save(),
        ),
        if (_missing == key)
          WText(
            Lang.get('components.unit_draft.required'),
            className: 'text-xs text-expired',
          ),
      ],
    );
  }
}
