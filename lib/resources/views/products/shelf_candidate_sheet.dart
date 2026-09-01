import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart'
    show ButtonIntent, MSBottomSheet, MSButton, MSCombobox, MSInput;

import '../../../app/models/shelf_read.dart';
import '../../../app/support/unit_label.dart';

/// What the user decided about one region of a shelf photograph.
///
/// Three outcomes rather than two, because a region the model could not name is not the same
/// question as one it named wrongly: [accepted] carries a product and a count, [rejected] says this
/// was never stock, and a dismissal says nothing at all and leaves the row where it was.
@immutable
class ShelfDecision {
  /// The product this region is being counted as, when it is being accepted.
  final String? productId;

  /// A name to create a product from, when the region had none and the user typed one.
  final String? newProductName;

  /// The Rec 20 code the created product will be counted in.
  ///
  /// Only meaningful alongside [newProductName]: an existing product already has one, and changing
  /// it would change what every quantity in its ledger means. D54 allows that in a draft and nowhere
  /// else.
  final String? newProductUnit;

  /// How many of it. Always at least one on an acceptance.
  final num quantity;

  /// Whether the user said this is not a product at all.
  final bool isRejection;

  /// Count this region as an existing product.
  const ShelfDecision.accepted({required String this.productId, required this.quantity})
    : newProductName = null,
      newProductUnit = null,
      isRejection = false;

  /// Count this region as a product that has to be created first.
  const ShelfDecision.named({
    required String this.newProductName,
    required this.quantity,
    this.newProductUnit,
  }) : productId = null,
       isRejection = false;

  /// This region is not stock.
  const ShelfDecision.rejected()
    : productId = null,
      newProductName = null,
      newProductUnit = null,
      quantity = 1,
      isRejection = true;
}

/// One region of a shelf photograph, and the three things a user can say about it.
///
/// **A sheet rather than an inline editor, and the reason is the photograph.** D60 keeps the picture
/// on screen through the whole review, so the list underneath it is already competing for a phone's
/// height; an expanding row would push the boxes off exactly when the user needs to look at them.
///
/// ### The name field appears only when there is nothing to accept
///
/// A matched region already has a product, so the only questions are how many and whether it is
/// really stock. An unresolved one has neither, and `ai-enrichment.md` requires it to be PRESENTED
/// rather than invented: the user is the one who knows what the bottle is, so they type it and the
/// product is created before the shelf commits.
class ShelfCandidateSheet extends StatefulWidget {
  /// The region being decided.
  final ShelfCandidate candidate;

  /// The unit codes this tenant may pick from, when a product has to be created.
  ///
  /// Comes from `GET /units`, so a tenant unit is selectable here as well. The caller fetches it,
  /// because a sheet opened per region would otherwise issue the same request six times.
  final List<String> unitCodes;

  /// Creates the [ShelfCandidateSheet].
  const ShelfCandidateSheet({
    super.key,
    required this.candidate,
    this.unitCodes = const <String>['C62'],
  });

  /// Opens the sheet and answers with what the user decided, or null on a dismissal.
  static Future<ShelfDecision?> show(
    BuildContext context, {
    required ShelfCandidate candidate,
    List<String> unitCodes = const <String>['C62'],
  }) {
    return MSBottomSheet.show<ShelfDecision>(
      context,
      title: Lang.get('screens.shelf_candidate.title', {'region': candidate.region}),
      description: candidate.productName ?? Lang.get('screens.shelf_candidate.unnamed'),
      body: ShelfCandidateSheet(candidate: candidate, unitCodes: unitCodes),
    );
  }

  @override
  State<ShelfCandidateSheet> createState() => _ShelfCandidateSheetState();
}

class _ShelfCandidateSheetState extends State<ShelfCandidateSheet> {
  late final TextEditingController _name;
  late final TextEditingController _quantity;

  String _unit = 'C62';

  /// Whether this region needs a product invented before it can be accepted.
  bool get _needsName => widget.candidate.productId == null;

  @override
  void initState() {
    super.initState();

    _name = TextEditingController(text: widget.candidate.productName ?? '');
    // **One rather than empty when the model could not count.** The user is looking at a region they
    // can see, and the server refuses a zero, so the field opens on the answer they most likely
    // want instead of on a blank they have to fill before the button works.
    _quantity = TextEditingController(text: '${widget.candidate.quantity ?? 1}');

    if (widget.unitCodes.isNotEmpty) _unit = widget.unitCodes.first;
  }

  @override
  void dispose() {
    _name.dispose();
    _quantity.dispose();
    super.dispose();
  }

  /// The quantity as a number, or null when the box does not hold one.
  ///
  /// Parsed on every read rather than held as a `num`, because a field the user is halfway through
  /// clearing is not a number and holding the last parsable value would submit something they can no
  /// longer see. The product-form path learned this on its own quantity field.
  num? get _parsed {
    final num? value = num.tryParse(_quantity.text.trim().replaceAll(',', '.'));

    return value != null && value > 0 ? value : null;
  }

  bool get _canAccept =>
      _parsed != null && (!_needsName || _name.text.trim().isNotEmpty);

  @override
  Widget build(BuildContext context) {
    return WDiv(
      className: 'flex flex-col gap-4',
      children: [
        if (_needsName)
          WDiv(
            className: 'flex flex-col gap-2',
            children: [
              WText(
                Lang.get('screens.shelf_candidate.name'),
                className: 'text-xs font-medium uppercase tracking-wide text-fg-muted',
              ),
              MSInput(
                controller: _name,
                className: 'bg-surface-container',
                placeholder: Lang.get('screens.shelf_candidate.name_placeholder'),
                onChanged: (_) => setState(() {}),
              ),
              _buildUnits(),
            ],
          ),
        WDiv(
          className: 'flex flex-col gap-2',
          children: [
            WText(
              Lang.get('screens.shelf_candidate.quantity'),
              className: 'text-xs font-medium uppercase tracking-wide text-fg-muted',
            ),
            MSInput(
              controller: _quantity,
              className: 'bg-surface-container',
              type: InputType.number,
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
        MSButton(
          onPressed: _canAccept ? _accept : null,
          disabled: !_canAccept,
          // The intent carries the disabled state because the disabled STYLE does not: measured on
          // this repo, `MSButton`'s disabled produces no visible change on the primary intent.
          intent: _canAccept ? ButtonIntent.primary : ButtonIntent.secondary,
          fullWidth: true,
          className: 'justify-center',
          child: WText(Lang.get('screens.shelf_candidate.accept')),
        ),
        MSButton(
          onPressed: () => Navigator.of(context).pop(const ShelfDecision.rejected()),
          intent: ButtonIntent.ghost,
          fullWidth: true,
          className: 'justify-center',
          child: WText(Lang.get('screens.shelf_candidate.reject')),
        ),
      ],
    );
  }

  /// The unit a created product will be counted in.
  ///
  /// Only shown alongside the name field, because an existing product already has one and changing
  /// it here would change what every quantity in its ledger means (D54 allows that in a draft and
  /// nowhere else).
  ///
  /// **A combobox rather than a row of chips, and the product form settled that already.** Nineteen
  /// codes are seeded and a tenant may register more, so the vocabulary has no known length: chips
  /// wrapped to two rows there before they were replaced, and a hand-picked subset here would have
  /// made a tenant's own unit unreachable on this path. The CODE picks and the WORD shows, because
  /// Rec 20 codes are unreadable by design.
  Widget _buildUnits() {
    return MSCombobox<String>(
      value: _unit,
      options: <SelectOption<String>>[
        for (final String code in widget.unitCodes)
          SelectOption<String>(value: code, label: unitLabel(code)),
      ],
      searchPlaceholder: Lang.get('screens.product_form.unit_search'),
      onChange: (String? next) {
        if (next != null) setState(() => _unit = next);
      },
    );
  }

  void _accept() {
    final num quantity = _parsed!;

    Navigator.of(context).pop(
      _needsName
          ? ShelfDecision.named(
              newProductName: _name.text.trim(),
              quantity: quantity,
              newProductUnit: _unit,
            )
          : ShelfDecision.accepted(productId: widget.candidate.productId!, quantity: quantity),
    );
  }
}
