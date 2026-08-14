import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart'
    show MSButton, ButtonIntent, MSInput, MSSwitch;

import '../../../app/models/scan_entry.dart' show ScanEntry;
import '../../../ui/components/section_header/section_header.dart';

/// What the sheet came back with: the card the user confirmed.
@immutable
class ScanDraft {
  /// The product's name. Required, and the only field that is.
  final String name;

  /// What one unit is counted in. Defaults to the countable one.
  final String baseUnit;

  /// The brand, when the user gave one.
  final String? brand;

  /// Whether this card goes to the shared catalogue (D117: ticked by default).
  final bool contribute;

  /// Creates a [ScanDraft].
  const ScanDraft({
    required this.name,
    required this.baseUnit,
    this.brand,
    this.contribute = true,
  });
}

/// Confirming or filling in what a scanned barcode is, without leaving the scan screen.
///
/// **A sheet rather than a route, because the camera never closes** (`barcode-and-catalog.md`'s third
/// criterion). Somebody unpacking twenty boxes cannot lose the viewfinder and the queue every time a
/// barcode is new to them, and a full-screen form would also drop the scanning session on the way
/// back.
///
/// ### Two entry states, one sheet
///
/// **Prefilled** when the cascade found the product: the catalogue or Open Food Facts already knows
/// what this barcode is, so the user reads one line and taps once. Nothing to type, which is the
/// whole point of the catalogue existing.
///
/// **Empty** when nothing anywhere knew it. Then the name is the only thing asked for outright.
///
/// Either way the fields are editable, because a catalogue answer can be wrong or in the wrong
/// language and the person holding the carton is the one who can see that.
///
/// ### Why the name is the only required field
///
/// `ai-enrichment.md` asks only for high-impact fields, and at a receiving bench the impact ranking
/// is not close: without a name the row cannot be read back at all, while a missing brand costs
/// nothing today and a missing category costs a filter facet later. Both are on the product screen,
/// which is where somebody sitting down fills them in.
///
/// The unit is second and it is PREFILLED rather than asked, at `piece`, because that is what most of
/// a delivery is and because D54 makes the unit freely editable only before stock exists: once a
/// movement is written, changing it reinterprets every quantity in the ledger. So it is offered here,
/// where it is still free, and not made a gate.
@immutable
class ScanDraftSheet extends StatefulWidget {
  /// The barcode this card will carry, shown so the user can check it against the label in hand.
  final String barcode;

  /// The name the cascade found, when it found one.
  final String? name;

  /// The brand the cascade found, when it found one.
  final String? brand;

  /// The unit this row is already counted in.
  ///
  /// **Passed rather than defaulted, because reopening the card was overwriting it.** The field always
  /// started at the default, so somebody who had set a row to `kg`, tapped it again to check, and
  /// pressed the button got `piece` back with no warning. That is silent loss on the one field D54
  /// says reinterprets every quantity in the ledger once a movement exists, which makes it the worst
  /// field in this sheet to get wrong.
  final String baseUnit;

  /// Where the answer came from, already localised, or null when nothing answered.
  final String? provenance;

  /// Whether the fields can be changed.
  ///
  /// **False for a product the tenant already owns**, and that is a correction rather than a
  /// restriction. Renaming one here would commit as a card to create, which the server refuses
  /// outright because the barcode is already linked to their product: a guaranteed 422 in exchange
  /// for an edit that belongs on the product screen. The sheet says where instead of failing.
  final bool editable;

  /// Whether the card arrived with an answer to confirm rather than an empty form to fill.
  ///
  /// **Only the primary button's word changes, and the word is the whole point.** `Save` on a card the
  /// user has not typed a character into describes the wrong act: they are agreeing with a name a
  /// shared catalogue supplied, and `Confirm` says that. The fields stay editable either way, because
  /// a catalogue answer can be wrong or in the wrong language and the person holding the carton is the
  /// one who can see it.
  final bool confirming;

  /// Creates the [ScanDraftSheet].
  const ScanDraftSheet({
    required this.barcode,
    this.name,
    this.brand,
    this.provenance,
    this.editable = true,
    this.confirming = false,
    this.baseUnit = ScanEntry.defaultUnit,
    super.key,
  });

  @override
  State<ScanDraftSheet> createState() => _ScanDraftSheetState();
}

class _ScanDraftSheetState extends State<ScanDraftSheet> {
  /// The unit a delivery is overwhelmingly counted in.
  ///
  /// **Taken from [ScanEntry] rather than declared here**, which was a review finding worth keeping:
  /// this sheet had its own copy, so the client held two unit vocabularies at once and a draft saved
  /// untouched sent a unit the rest of the app did not use. One constant, and the server writes the
  /// same value when a line omits it.
  ///
  /// It is the fallback for an EMPTY field now rather than the field's starting value, which is
  /// [ScanDraftSheet.baseUnit].
  static const String _defaultUnit = ScanEntry.defaultUnit;

  late final TextEditingController _name = TextEditingController(
    text: widget.name ?? '',
  );
  late final TextEditingController _brand = TextEditingController(
    text: widget.brand ?? '',
  );
  late final TextEditingController _unit = TextEditingController(
    text: widget.baseUnit,
  );

  bool _contribute = true;

  /// Whether the name has been emptied, so the button can say why it will not proceed.
  bool _nameMissing = false;

  @override
  void dispose() {
    _name.dispose();
    _brand.dispose();
    _unit.dispose();
    super.dispose();
  }

  void _save() {
    final String name = _name.text.trim();

    if (name.isEmpty) {
      // **Named rather than silently refused.** A disabled button with no reason is the shape a user
      // reads as broken, and the name is the one thing this sheet cannot guess.
      setState(() => _nameMissing = true);

      return;
    }

    final String unit = _unit.text.trim();
    final String brand = _brand.text.trim();

    Navigator.of(context).pop(
      ScanDraft(
        name: name,
        baseUnit: unit.isEmpty ? _defaultUnit : unit,
        brand: brand.isEmpty ? null : brand,
        contribute: _contribute,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WDiv(
      className: 'flex flex-col gap-4',
      children: [
        // **The barcode, always, in mono.** Resolution is a claim about a machine reading, and the
        // label in the user's hand is the only thing they can check it against. Same reasoning
        // `ScanRow` records for showing it after a confident match.
        WDiv(
          className: 'flex flex-col gap-1',
          children: [
            WText(
              Lang.get('components.scan_draft.barcode_label'),
              className: 'text-xs font-medium text-fg-muted',
            ),
            WText(widget.barcode, className: 'font-mono text-sm text-fg'),
            // Where the answer came from, when one did. Absent for a code nothing knew, where
            // printing "no source" would be a line about nothing.
            if (widget.provenance != null)
              WText(widget.provenance!, className: 'text-xs text-fg-muted'),
          ],
        ),
        SectionHeader(label: Lang.get('components.scan_draft.product_group')),
        // Read-only, with the reason and the place to do it instead. A field that accepts typing and
        // then discards it is worse than one that cannot be typed into.
        if (!widget.editable) ...[
          WText(widget.name ?? '', className: 'text-sm font-medium text-fg'),
          WText(
            Lang.get('components.scan_draft.owned_note'),
            className: 'text-xs text-fg-muted',
          ),
        ] else
          WDiv(
            className: 'flex flex-col gap-1',
            children: [
              MSInput(
                className: 'bg-surface-container px-3 py-3.5',
                placeholder: Lang.get('components.scan_draft.name_placeholder'),
                controller: _name,
                // Cleared on the first keystroke, because the complaint is about an empty field and it
                // stops being true the moment they type.
                onChanged: (String _) {
                  if (_nameMissing) setState(() => _nameMissing = false);
                },
                onSubmitted: (String _) => _save(),
              ),
              if (_nameMissing)
                WText(
                  Lang.get('components.scan_draft.name_required'),
                  className: 'text-xs text-expired',
                ),
            ],
          ),
        // Optional, and labelled as such rather than left to be guessed: a bench that leaves both
        // blank has lost nothing, and the product screen is where they get filled in.
        if (widget.editable)
          WDiv(
            className: 'flex flex-col md:flex-row gap-2',
            children: [
              WDiv(
                className: 'flex-1 min-w-0 flex flex-col gap-1',
                children: [
                  WText(
                    Lang.get('components.scan_draft.unit_label'),
                    className: 'text-xs text-fg-muted',
                  ),
                  MSInput(
                    className: 'bg-surface-container px-3 py-3.5',
                    controller: _unit,
                  ),
                ],
              ),
              WDiv(
                className: 'flex-1 min-w-0 flex flex-col gap-1',
                children: [
                  WText(
                    Lang.get('components.scan_draft.brand_label'),
                    className: 'text-xs text-fg-muted',
                  ),
                  MSInput(
                    className: 'bg-surface-container px-3 py-3.5',
                    placeholder: Lang.get('components.scan_draft.optional'),
                    controller: _brand,
                  ),
                ],
              ),
            ],
          ),
        // D117: ticked, and visible at the moment the thing being shared is on screen. Absent for an
        // owned product, which is already in the tenant's catalogue and has nothing new to share. The
        // switch carries `border-color-control` because its shape IS the whole control, and on a card
        // its own track measured 1.21:1 without it.
        if (widget.editable)
          WDiv(
            className: 'flex flex-row items-center justify-between gap-3',
            children: [
              WDiv(
                className: 'flex-1 min-w-0 flex flex-col',
                children: [
                  WText(
                    Lang.get('components.scan_draft.contribute_label'),
                    className: 'text-sm text-fg',
                  ),
                  WText(
                    Lang.get('components.scan_draft.contribute_note'),
                    className: 'text-xs text-fg-muted',
                  ),
                ],
              ),
              MSSwitch(
                value: _contribute,
                className: 'border border-color-control shrink-0',
                onChanged: (bool value) => setState(() => _contribute = value),
              ),
            ],
          ),
        if (widget.editable)
          MSButton(
            onPressed: _save,
            fullWidth: true,
            className: 'justify-center',
            child: WText(
              Lang.get(
                widget.confirming
                    ? 'components.scan_draft.confirm'
                    : 'components.scan_draft.save',
              ),
            ),
          ),
        MSButton(
          onPressed: () => Navigator.of(context).pop(),
          intent: widget.editable ? ButtonIntent.ghost : ButtonIntent.primary,
          fullWidth: true,
          className: 'justify-center',
          child: WText(
            Lang.get(
              widget.editable
                  ? 'components.scan_draft.cancel'
                  : 'components.scan_draft.done',
            ),
          ),
        ),
      ],
    );
  }
}
