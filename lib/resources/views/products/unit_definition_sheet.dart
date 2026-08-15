import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart' show ButtonIntent, MSBottomSheet, MSButton, MSInput;

import '../../../app/support/unit_label.dart';

/// Teaching the app a purchase unit it has never seen, without stopping what the user was doing.
///
/// ### Why this is a sheet and not an error
///
/// `inventory-core.md` draws this mockup itself and states the rule beside it: an unknown unit does
/// not block the capture, it offers a one-time definition. That distinction is the whole design.
/// "2 koli su" is a completely reasonable thing for a person to say, and a product that answers it
/// with "unknown unit" is teaching the user its own vocabulary instead of learning theirs.
///
/// It reaches every capture path, which is why it is a sheet over whatever screen asked: the
/// assistant parsing a sentence, a receipt line, and the manual stock-in form can all meet a `koli`
/// for the first time.
///
/// ### One number, and the result stated back
///
/// The only thing the app cannot work out is the factor, so that is the only field. Everything else
/// on screen is there to make the answer checkable: the sentence reads as an equation, and the line
/// underneath says what the entered number means for the quantity the user actually typed.
///
/// A wrong factor is quiet and expensive. It does not fail; it silently multiplies every future
/// purchase in that unit, and the error surfaces weeks later as a stock figure nobody can explain.
/// Restating the consequence is cheap insurance against a mistyped digit.
@immutable
class UnitDefinitionSheet extends StatefulWidget {
  /// The unit the user said, as they said it.
  final String unit;

  /// The product's base unit, which the factor converts into.
  final String baseUnit;

  /// How many [unit] the user is recording, used to state the consequence.
  final num quantity;

  /// Creates a [UnitDefinitionSheet].
  const UnitDefinitionSheet({
    super.key,
    required this.unit,
    required this.baseUnit,
    this.quantity = 1,
  });

  /// Opens the sheet and resolves to the factor, or null when the user backs out.
  static Future<num?> show(
    BuildContext context, {
    required String unit,
    required String baseUnit,
    num quantity = 1,
  }) {
    return MSBottomSheet.show<num>(
      context,
      title: Lang.get('screens.unit_definition.title', {'unit': unit}),
      description: Lang.get('screens.unit_definition.description'),
      body: UnitDefinitionSheet(unit: unit, baseUnit: baseUnit, quantity: quantity),
    );
  }

  @override
  State<UnitDefinitionSheet> createState() => _UnitDefinitionSheetState();
}

class _UnitDefinitionSheetState extends State<UnitDefinitionSheet> {
  num? _factor;

  bool get _isValid => (_factor ?? 0) > 0;

  @override
  Widget build(BuildContext context) {
    return WDiv(
      className: 'flex flex-col gap-4 w-full',
      children: [
        _buildEquation(),
        if (_isValid) _buildConsequence(),
        _buildActions(),
      ],
    );
  }

  /// `1 koli = [__] adet`, laid out as the sentence it is.
  ///
  /// The two fixed words sit either side of the only input, so the field cannot be misread as
  /// asking for anything else. It wraps to a column at narrow widths rather than shrinking the
  /// input, because a two-character number box is worse than a second line.
  Widget _buildEquation() {
    return WDiv(
      className: 'flex flex-col sm:flex-row sm:items-center gap-2 w-full',
      children: [
        WText(
          Lang.get('screens.unit_definition.one', {'unit': widget.unit}),
          className: 'text-base font-semibold text-fg shrink-0',
        ),
        WDiv(
          className: 'flex flex-row items-center gap-2 flex-1 min-w-0',
          children: [
            WDiv(
              className: 'flex-1 min-w-0',
              child: MSInput(
                className: 'h-11 bg-surface-container',
                placeholder: Lang.get('screens.unit_definition.placeholder'),
                semanticLabel: Lang.get('screens.unit_definition.factor_label', {
                  'unit': widget.unit,
                  'base': unitLabel(widget.baseUnit, 1),
                }),
                onChanged: (String next) => setState(() => _factor = num.tryParse(next)),
              ),
            ),
            WText(
              unitLabel(widget.baseUnit, _factor ?? 1),
              className: 'text-base font-semibold text-fg shrink-0',
            ),
          ],
        ),
      ],
    );
  }

  /// What the factor means for the quantity actually being recorded.
  Widget _buildConsequence() {
    return WText(
      Lang.get('screens.unit_definition.result', {
        'quantity': widget.quantity,
        'unit': widget.unit,
        'total': widget.quantity * _factor!,
        'base': unitLabel(widget.baseUnit, widget.quantity * _factor!),
      }),
      className: 'text-sm text-fg-muted',
    );
  }

  Widget _buildActions() {
    return WDiv(
      className: 'flex flex-col gap-2 w-full',
      children: [
        MSButton(
          onPressed: _isValid ? () => Navigator.of(context).pop(_factor) : null,
          disabled: !_isValid,
          // The fill carries the disabled state, because MSButton's disabled styling does not.
          intent: _isValid ? ButtonIntent.primary : ButtonIntent.secondary,
          fullWidth: true,
          className: 'justify-center',
          child: WText(Lang.get('screens.unit_definition.save')),
        ),
        // Backing out is not an error path: the user can still record the purchase in the base
        // unit, which is what `inventory-core.md` means by not blocking them.
        MSButton(
          onPressed: () => Navigator.of(context).pop(),
          intent: ButtonIntent.ghost,
          fullWidth: true,
          className: 'justify-center',
          child: WText(Lang.get('screens.unit_definition.cancel', {'base': unitLabel(widget.baseUnit, 1)})),
        ),
      ],
    );
  }
}
